open Cesia
open Types

(* debug.ReadLine: on a terminal, the keys edit the line and walk the history of the lines read; elsewhere, as from a pipe,
   lines are read as they come. While it waits, the other fibers of the program run, but at a stop of the debugger. *)

type state = {
  poll : Poll.t;
  mutable buf : string;  (* read and not yet taken *)
  mutable at : int;
  mutable parked : bool;  (* the input is watched, so a fiber can wait for it *)
  mutable history : string list;  (* the last line first *)
}

let create poll = { poll; buf = ""; at = 0; parked = false; history = [] }
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

let out s = print_string s; flush stdout

(* The keys of a line being edited: its characters, each a UTF-8 sequence, and the cursor before the one of that rank. *)
let edit st ctx prompt =
  let line = ref [||] and cur = ref 0 and back = ref (-1) and saved = ref [||] in
  let text () = String.concat "" (Array.to_list !line) in
  let show () =
    let n = Array.length !line in
    out ("\r" ^ prompt ^ text () ^ "\027[K" ^ if !cur < n then Printf.sprintf "\027[%dD" (n - !cur) else "")
  in
  let set chars = line := chars; cur := Array.length chars in
  let chars s =
    let acc = ref [] and i = ref 0 in
    while !i < String.length s do
      let n = Uchar.utf_decode_length (String.get_utf_8_uchar s !i) in
      acc := String.sub s !i n :: !acc;
      i := !i + n
    done;
    Array.of_list (List.rev !acc)
  in
  let walk d =
    let k = !back + d in
    if k >= -1 && k < List.length st.history then begin
      if !back = -1 then saved := !line;
      back := k;
      set (if k = -1 then !saved else chars (List.nth st.history k))
    end
  in
  let insert c =
    line := Array.concat [ Array.sub !line 0 !cur; [| c |]; Array.sub !line !cur (Array.length !line - !cur) ];
    incr cur
  in
  let cut a b = line := Array.append (Array.sub !line 0 a) (Array.sub !line b (Array.length !line - b)) in
  let rec utf8 first =
    let need = if first >= '\xf0' then 3 else if first >= '\xe0' then 2 else if first >= '\xc0' then 1 else 0 in
    let b = Buffer.create 4 in
    Buffer.add_char b first;
    for _ = 1 to need do Option.iter (Buffer.add_char b) (byte st ctx) done;
    Buffer.contents b
  and escape () =
    match byte st ctx with
    | Some ('[' | 'O') ->
      let rec final acc = match byte st ctx with Some ('0' .. '9' as c) -> final (acc ^ String.make 1 c) | c -> acc, c in
      (match final "" with
       | _, Some 'A' -> walk 1
       | _, Some 'B' -> walk (-1)
       | _, Some 'C' -> cur := min (Array.length !line) (!cur + 1)
       | _, Some 'D' -> cur := max 0 (!cur - 1)
       | _, Some 'H' | ("1" | "7"), Some '~' -> cur := 0
       | _, Some 'F' | ("4" | "8"), Some '~' -> cur := Array.length !line
       | "3", Some '~' -> if !cur < Array.length !line then cut !cur (!cur + 1)
       | _ -> ())
    | _ -> ()
  and key () =
    show ();
    match byte st ctx with
    | None -> None
    | Some ('\r' | '\n') -> out "\r\n"; Some (text ())
    | Some '\004' when !line = [||] -> out "\r\n"; None
    | Some '\004' -> if !cur < Array.length !line then cut !cur (!cur + 1); key ()
    | Some '\003' when !line = [||] ->
      (* At an empty prompt, Ctrl-C stops the program, as everywhere. *)
      out "\r\n";
      Unix.kill (Unix.getpid ()) Sys.sigint;
      key ()
    | Some '\003' -> out "^C\r\n"; set [||]; key ()
    | Some ('\127' | '\b') -> if !cur > 0 then (cut (!cur - 1) !cur; decr cur); key ()
    | Some '\001' -> cur := 0; key ()
    | Some '\005' -> cur := Array.length !line; key ()
    | Some '\002' -> cur := max 0 (!cur - 1); key ()
    | Some '\006' -> cur := min (Array.length !line) (!cur + 1); key ()
    | Some '\011' -> cut !cur (Array.length !line); key ()
    | Some '\021' -> cut 0 !cur; cur := 0; key ()
    | Some '\023' ->
      let k = ref !cur in
      while !k > 0 && !line.(!k - 1) = " " do decr k done;
      while !k > 0 && !line.(!k - 1) <> " " do decr k done;
      cut !k !cur;
      cur := !k;
      key ()
    | Some '\016' -> walk 1; key ()
    | Some '\014' -> walk (-1); key ()
    | Some '\012' -> out "\027[H\027[2J"; key ()
    | Some '\027' -> escape (); key ()
    | Some '\t' -> insert " "; insert " "; key ()
    | Some c when c >= ' ' -> insert (utf8 c); key ()
    | Some _ -> key ()
  in
  key ()

(* The terminal gives each key as it comes, without echo, for the time of one line. *)
let raw () =
  match Unix.tcgetattr Unix.stdin with
  | t ->
    Unix.tcsetattr Unix.stdin Unix.TCSANOW { t with c_icanon = false; c_echo = false; c_isig = false; c_vmin = 1; c_vtime = 0 };
    Some t
  | exception (Unix.Unix_error _ | Invalid_argument _) -> None

let terminal = lazy (try Unix.isatty Unix.stdin && Unix.isatty Unix.stdout with Unix.Unix_error _ -> false)

let read_line st ctx (a : Types.t array) =
  let prompt = if Array.length a > 0 then Native.text_arg ctx "ReadLine" a.(0) else "" in
  Runtime.flush_out ctx.w;
  let got =
    if not (Lazy.force terminal) then plain st ctx
    else
      match raw () with
      | None -> out prompt; plain st ctx
      | Some before ->
        let restore () = try Unix.tcsetattr Unix.stdin Unix.TCSANOW before with Unix.Unix_error _ -> () in
        Fun.protect ~finally:restore (fun () -> edit st ctx prompt)
  in
  match got with
  | None -> Missing
  | Some l ->
    if l <> "" && (match st.history with h :: _ -> h <> l | [] -> true) then st.history <- l :: st.history;
    Text l

let natives poll =
  let st = create poll in
  [ "ReadLine", Native.nat ~perm:Debug ~params:[| "prompt" |] "ReadLine" 0 1 (read_line st) ]
