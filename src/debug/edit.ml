(* The line editor of debug.ReadLine on a terminal: the keys edit the line and walk the history of the lines read before.
   [byte] gives the next byte of the input, or [None] at its end; the reading itself, which waits as a fiber does, stays in
   the binary (src/sys/term.ml). *)

let out s = print_string s; flush stdout

(* The terminal as it was before a line was edited: given back after the line, and at the exit if the program ends while
   a fiber edits one. *)
let cooked = ref None

let restore () =
  Option.iter (fun t -> try Unix.tcsetattr Unix.stdin Unix.TCSANOW t with Unix.Unix_error _ -> ()) !cooked;
  cooked := None

let () = at_exit restore

(* The keys of a line being edited: its characters, each a UTF-8 sequence, and the cursor before the one of that rank. *)
let edit history byte prompt =
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
    if k >= -1 && k < List.length !history then begin
      if !back = -1 then saved := !line;
      back := k;
      set (if k = -1 then !saved else chars (List.nth !history k))
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
    for _ = 1 to need do Option.iter (Buffer.add_char b) (byte ()) done;
    Buffer.contents b
  and escape () =
    match byte () with
    | Some ('[' | 'O') ->
      let rec final acc = match byte () with Some ('0' .. '9' as c) -> final (acc ^ String.make 1 c) | c -> acc, c in
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
    match byte () with
    | None -> None
    | Some ('\r' | '\n') -> out "\r\n"; Some (text ())
    | Some '\004' when !line = [||] -> out "\r\n"; None
    | Some '\004' -> if !cur < Array.length !line then cut !cur (!cur + 1); key ()
    | Some '\003' when !line = [||] ->
      (* At an empty prompt, Ctrl-C stops the program, as everywhere, the terminal given back first. *)
      out "\r\n";
      restore ();
      Unix.kill (Unix.getpid ()) Sys.sigint;
      Some ""
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

let history = ref []

(* A line edited on the terminal, with the prompt before it; [None] at the end of the input. *)
let line prompt byte =
  match raw () with
  | None ->
    out prompt;
    let b = Buffer.create 80 in
    let rec go () = match byte () with Some '\n' | None -> () | Some c -> Buffer.add_char b c; go () in
    go ();
    Some (Buffer.contents b)
  | Some before ->
    cooked := Some before;
    let got = Fun.protect ~finally:restore (fun () -> edit history byte prompt) in
    Option.iter (fun l -> if l <> "" && (match !history with h :: _ -> h <> l | [] -> true) then history := l :: !history) got;
    got
