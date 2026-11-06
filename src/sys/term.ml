open Cesia
open Types

(* debug.ReadLine: lines of the standard input as they come, from a pipe, a file or a terminal, where the line editor of
   the plugin of the debugger's engine edits them. While it waits, the other fibers of the program run, but at a stop of
   the debugger. *)

type state = {
  poll : Poll.t;
  mutable buf : string;  (* read and not yet taken *)
  mutable at : int;
  mutable parked : bool;  (* the input is watched, so a fiber can wait for it *)
}

let create poll = { poll; buf = ""; at = 0; parked = false }
let chunk = Bytes.create 4096

(* A pipe, a socket or a terminal can be waited for; a file or /dev/null never makes one wait. *)
let waitable =
  lazy
    (match (Unix.fstat Unix.stdin).st_kind with
     | S_FIFO | S_SOCK -> true
     | S_CHR -> Unix.isatty Unix.stdin
     | _ -> false
     | exception Unix.Unix_error _ -> false)

(* The input watched, so that a fiber can wait for it while the others run; but at a stop of the debugger, which holds the
   program, or on a system that can't wait for it. *)
let watch st ctx =
  if not (st.parked || ctx.w.debug.stopped || Sys.win32) && Lazy.force waitable then begin
    Poll.watch st.poll Unix.stdin;
    st.parked <- true;
    at_exit (fun () -> try Unix.clear_nonblock Unix.stdin with Unix.Unix_error _ -> ())
  end

(* The next byte, or [None] at the end of the input. A read comes first, the wait after: the input says only when it
   changes. *)
let rec byte st ctx =
  if st.at < String.length st.buf then begin
    st.at <- st.at + 1;
    Some st.buf.[st.at - 1]
  end
  else begin
    watch st ctx;
    match Unix.read Unix.stdin chunk 0 4096 with
    | 0 -> None
    | n ->
      st.buf <- Bytes.sub_string chunk 0 n;
      st.at <- 0;
      byte st ctx
    | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
      if ctx.w.debug.stopped || not st.parked then ignore (Unix.select [ Unix.stdin ] [] [] (-1.))
      else Poll.read_ready st.poll ctx Unix.stdin;
      byte st ctx
    | exception Unix.Unix_error _ -> None
  end

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

let natives ~editor poll =
  let st = create poll in
  [ "ReadLine", Native.nat ~perm:Debug ~params:[| "prompt" |] "ReadLine" 0 1 (read_line ~editor st) ]
