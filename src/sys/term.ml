open Cesia
open Types

(* The standard input, read through one buffer: sys.ReadInput takes bytes of it, debug.ReadLine lines, as they come, from a
   pipe, a file or a terminal, where the line editor of the plugin of the debugger's engine edits them. While a fiber waits
   for it, the other fibers of the program run, but at a stop of the debugger. *)

type state = {
  poll : Poll.t;
  mutable buf : string;  (* read and not yet taken *)
  mutable at : int;
  mutable parked : bool;  (* the input is watched, so a fiber can wait for it *)
}

let create poll = { poll; buf = ""; at = 0; parked = false }
(* Made at the first read: a program that never reads its input doesn't pay for it, nor does its limit of memory. *)
let chunk_size = 65536
let chunk = lazy (Bytes.create chunk_size)

(* A pipe, a socket or a terminal can be waited for; a file or /dev/null never makes one wait. *)
let waitable =
  lazy
    (match (Unix.fstat Unix.stdin).st_kind with
     | S_FIFO | S_SOCK -> true
     | S_CHR -> Unix.isatty Unix.stdin
     | _ -> false
     | exception Unix.Unix_error _ -> false)

(* The input that a fiber waited for goes back to blocking when the program ends: the shell shares it. *)
let blocking_at_exit = lazy (at_exit (fun () -> try Unix.clear_nonblock Unix.stdin with Unix.Unix_error _ -> ()))

(* The input watched, so that a fiber can wait for it while the others run; but at a stop of the debugger, which holds the
   program, or on a system that can't wait for it. *)
let watch st ctx =
  if not (st.parked || ctx.w.debug.stopped || Sys.win32) && Lazy.force waitable then begin
    Poll.watch st.poll Unix.stdin;
    st.parked <- true;
    Lazy.force blocking_at_exit
  end

(* Whether the buffer holds a byte, read first when it is empty: false at the end of the input. A read comes first, the
   wait after: the input says only when it changes. Raises [Unix.Unix_error] for a failed read. *)
let rec more st ctx =
  st.at < String.length st.buf
  || begin
    watch st ctx;
    let chunk = Lazy.force chunk in
    match Unix.read Unix.stdin chunk 0 chunk_size with
    | 0 -> false
    | n ->
      st.buf <- Bytes.sub_string chunk 0 n;
      st.at <- 0;
      (* Read at a stop, while a fiber waits for the input: the input won't say again what is now in the buffer, so the
         fiber wakes and looks there. *)
      if ctx.w.debug.stopped && st.parked then begin
        Poll.forget st.poll Unix.stdin;
        st.parked <- false
      end;
      true
    | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
      if ctx.w.debug.stopped || not st.parked then ignore (Unix.select [ Unix.stdin ] [] [] (-1.))
      else Poll.read_ready st.poll ctx Unix.stdin;
      more st ctx
  end

(* The next byte, or [None] at the end of the input or after a failed read. *)
let byte st ctx =
  match more st ctx with
  | true ->
    st.at <- st.at + 1;
    Some st.buf.[st.at - 1]
  | false -> None
  | exception Unix.Unix_error _ -> None

(* A line as it comes, without its line end; [None] at the end of the input. *)
let plain st ctx =
  let b = Buffer.create 80 in
  let rec go () =
    match byte st ctx with
    | Some '\n' -> Some (Buffer.contents b)
    | Some c -> Buffer.add_char b c; go ()
    | None -> if Buffer.length b = 0 then None else Some (Buffer.contents b)
  in
  Option.map (fun l -> if String.ends_with ~suffix:"\r" l then String.sub l 0 (String.length l - 1) else l) (go ())

let terminal = lazy (try Unix.isatty Unix.stdin && Unix.isatty Unix.stdout with Unix.Unix_error _ -> false)

let out s = print_string s; flush stdout

(* On a terminal, the line editor, in the plugin of the debugger's engine: without it, lines are read as from a pipe. *)
let read_line ~editor st ctx (a : Types.t array) =
  let prompt = if Array.length a > 0 then Native.text_arg ctx "ReadLine" a.(0) else "" in
  Runtime.flush_out ctx.w;
  let got =
    match if Lazy.force terminal then editor () else None with
    | Some edit -> edit prompt (fun () -> byte st ctx)
    | None -> if Lazy.force terminal then out prompt; plain st ctx
  in
  match got with
  | None -> Missing
  | Some l -> Text l

let natives ~editor st =
  [ "ReadLine", Native.nat ~perm:Debug ~params:[| "prompt" |] "ReadLine" 0 1 (read_line ~editor st) ]

(* sys.ReadInput(count): the next count bytes of the input, fewer only at its end; without a count, all of it up to its
   end. The fiber waits for it as for any input, and the other fibers run. It needs no permission: the input is the
   program's own. *)
let read_input st ctx (a : Types.t array) =
  let count =
    match if Array.length a > 0 then a.(0) else Missing with
    | Missing | Undef -> max_int
    | Int n when n >= 0 -> n
    | v -> Runtime.fail ctx Type (Messages.need_count "ReadInput" (Value.describe v))
  in
  let b = Buffer.create (min count chunk_size) in
  let rec go () =
    if Buffer.length b < count && more st ctx then begin
      let k = min (count - Buffer.length b) (String.length st.buf - st.at) in
      Runtime.build ctx ((k / 8) + 1);
      Buffer.add_substring b st.buf st.at k;
      st.at <- st.at + k;
      go ()
    end
  in
  match go () with
  | () -> Value.ok ctx.w (Text (Buffer.contents b))
  | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "read" "the standard input" e

let input st = [ "ReadInput", Native.nat ~result:true ~params:[| "count" |] "ReadInput" 0 1 (read_input st) ]
