open Kepler
open Types

type t = {
  poll : Poll.t;
  sockets : (int, Unix.file_descr) Hashtbl.t;
  deadlines : (int, float) Hashtbl.t;  (* net.arm: when a socket gets closed *)
  buffer : Bytes.t;  (* shared by reads: nothing suspends between a read and copying its bytes *)
  mutable stopping : bool;
  mutable handlers : bool;
}

let chunk_size = 65536
let exit_on_second_signal = 130

let create poll =
  { poll; sockets = Hashtbl.create 64; deadlines = Hashtbl.create 64; buffer = Bytes.create chunk_size; stopping = false; handlers = false }

let stopping n = n.stopping

(* The first stop signal asks accept to end; the second one doesn't wait. *)
let install_handlers n =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  if not n.handlers then begin
    n.handlers <- true;
    let stop =
      Sys.Signal_handle
        (fun _ ->
           if n.stopping then exit exit_on_second_signal;
           n.stopping <- true;
           Poll.interrupt n.poll)
    in
    Sys.set_signal Sys.sigint stop;
    Sys.set_signal Sys.sigterm stop
  end

let handle n (ctx : ctx) fd =
  let s = ctx.w.sched in
  let id = s.next_id in
  s.next_id <- id + 1;
  Hashtbl.replace n.sockets id fd;
  Poll.watch n.poll fd;
  Handle { kind = "socket"; id; task = None }

let socket_arg ctx name (v : Types.t) =
  match v with
  | Handle { kind = "socket"; id; _ } -> id
  | _ -> Runtime.fail ctx Type (Messages.need_socket name (Value.describe v))

let closed ctx = Fs.io_error ctx.w Messages.socket_closed.text

(* Runs [f] on an open socket. A closed one is an Err, not a panic. *)
let with_socket n ctx name v f =
  match Hashtbl.find_opt n.sockets (socket_arg ctx name v) with
  | Some fd -> f fd
  | None -> closed ctx

let stopped ctx = Fs.failure ctx.w "stopped" Messages.server_stopped.text

let port_arg ctx (v : Types.t) =
  match v with
  | Int p when p >= 0 && p < 65536 -> p
  | _ -> Runtime.fail ctx Type (Messages.need_port (Value.describe v))

let address host =
  try Unix.inet_addr_of_string host
  with Failure _ -> (Unix.gethostbyname host).Unix.h_addr_list.(0)

let family addr = Unix.domain_of_sockaddr (Unix.ADDR_INET (addr, 0))

let listen n ctx (a : Types.t array) =
  let port = port_arg ctx a.(0) in
  let host = if Array.length a > 1 && a.(1) != Undef then Native.text_arg ctx "listen" a.(1) else "127.0.0.1" in
  Runtime.check_perm ctx Net (Some (Printf.sprintf ":%d" port));
  install_handlers n;
  let target = Printf.sprintf "%s:%d" host port in
  match
    let addr = address host in
    let fd = Unix.socket ~cloexec:true (family addr) Unix.SOCK_STREAM 0 in
    (try
       Unix.setsockopt fd Unix.SO_REUSEADDR true;
       Unix.bind fd (Unix.ADDR_INET (addr, port));
       Unix.listen fd 4096;
       fd
     with e ->
       Unix.close fd;
       raise e)
  with
  | fd -> Value.ok ctx.w (handle n ctx fd)
  | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "listen on" target e
  | exception Not_found -> Fs.io_error ctx.w (Messages.io_failure "find" host "unknown host").text

let accept n ctx (a : Types.t array) =
  with_socket n ctx "accept" a.(0) (fun fd ->
      let rec go () =
        if n.stopping then stopped ctx
        else if Hashtbl.length n.sockets >= Backend.capacity then Fs.io_error ctx.w Messages.too_many_sockets.text
        else
          match Unix.accept ~cloexec:true fd with
          | c, _ ->
            Unix.setsockopt c Unix.TCP_NODELAY true;
            Value.ok ctx.w (handle n ctx c)
          | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
            Poll.read_ready n.poll ctx fd;
            if Hashtbl.mem n.sockets (socket_arg ctx "accept" a.(0)) then go () else closed ctx
          | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "accept on" "this socket" e
      in
      go ())

let connect n ctx (a : Types.t array) =
  let host = Native.text_arg ctx "connect" a.(0) and port = port_arg ctx a.(1) in
  let target = Printf.sprintf "%s:%d" host port in
  Runtime.check_perm ctx Net (Some target);
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  match address host with
  | exception Not_found -> Fs.io_error ctx.w (Messages.io_failure "find" host "unknown host").text
  | addr ->
    match Unix.socket ~cloexec:true (family addr) Unix.SOCK_STREAM 0 with
    | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "connect to" target e
    | fd ->
      let give_up e =
        Unix.close fd;
        Fs.failed ctx "connect to" target e
      in
      Unix.set_nonblock fd;
      let finish () =
        Unix.setsockopt fd Unix.TCP_NODELAY true;
        Value.ok ctx.w (handle n ctx fd)
      in
      (match Unix.connect fd (Unix.ADDR_INET (addr, port)) with
       | () -> finish ()
       | exception Unix.Unix_error (Unix.EINPROGRESS, _, _) ->
         Poll.watch n.poll fd;
         Poll.write_ready n.poll ctx fd;
         Poll.forget n.poll fd;
         (match Unix.getsockopt_error fd with
          | None -> finish ()
          | Some e -> give_up e)
       | exception Unix.Unix_error (e, _, _) -> give_up e)

let read n ctx (a : Types.t array) =
  let id = socket_arg ctx "read" a.(0) in
  let rec go () =
    match Hashtbl.find_opt n.sockets id with
    | None -> closed ctx
    | Some fd ->
      (match Unix.read fd n.buffer 0 chunk_size with
       | got -> Value.ok ctx.w (Text (Bytes.sub_string n.buffer 0 got))
       | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
         if n.stopping then stopped ctx
         else begin
           Poll.read_ready n.poll ctx fd;
           go ()
         end
       | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "read from" "this socket" e)
  in
  go ()

let write n ctx (a : Types.t array) =
  let id = socket_arg ctx "write" a.(0) in
  let text = Native.text_arg ctx "write" a.(1) in
  let size = String.length text in
  let rec go at =
    match Hashtbl.find_opt n.sockets id with
    | None -> closed ctx
    | Some _ when at >= size -> Value.ok ctx.w Missing
    | Some fd ->
      (match Unix.single_write_substring fd text at (size - at) with
       | sent -> go (at + sent)
       | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
         Poll.write_ready n.poll ctx fd;
         go at
       | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "write to" "this socket" e)
  in
  go 0

let close_socket n id =
  Hashtbl.remove n.deadlines id;
  match Hashtbl.find_opt n.sockets id with
  | None -> ()
  | Some fd ->
    Hashtbl.remove n.sockets id;
    Poll.forget n.poll fd;
    Unix.close fd

let close n ctx (a : Types.t array) =
  close_socket n (socket_arg ctx "close" a.(0));
  Missing

(* A socket that outlives its deadline is closed by net.reap, which wakes whoever waits on it: a slow client can't hold
   a fiber forever. 0 removes the deadline. *)
let arm n ctx (a : Types.t array) =
  let id = socket_arg ctx "arm" a.(0) in
  let seconds = match a.(1) with
    | Int i -> float_of_int i
    | Float x -> x
    | v -> Runtime.fail ctx Type (Messages.need_number "arm" (Value.describe v))
  in
  if seconds <= 0. then Hashtbl.remove n.deadlines id
  else if Hashtbl.mem n.sockets id then Hashtbl.replace n.deadlines id (Unix.gettimeofday () +. seconds);
  Missing

let reap n _ _ : Types.t =
  let now = Unix.gettimeofday () in
  let late = Hashtbl.fold (fun id t acc -> if t <= now then id :: acc else acc) n.deadlines [] in
  List.iter (close_socket n) late;
  Int (List.length late)

(* HTTP lengths count bytes, unlike length and slice, which count code points. *)
let find ctx (a : Types.t array) =
  let part = Native.text_arg ctx "find" a.(0) and text = Native.text_arg ctx "find" a.(1) in
  match if part = "" then 0 else Native.find_from text part 0 with
  | -1 -> Missing
  | at -> Int at

let split_at ctx (a : Types.t array) =
  let text = Native.text_arg ctx "split_at" a.(1) in
  match a.(0) with
  | Int k when k >= 0 && k <= String.length text ->
    Runtime.build ctx ((String.length text / 8) + 1);
    let items = [| Text (String.sub text 0 k); Text (String.sub text k (String.length text - k)) |] in
    Array { rows = 1; cols = 2; store = V items; a_owned = true }
  | v -> Runtime.fail ctx Type (Messages.need_size "split_at" (Value.describe v))

(* A header name, as RFC 9110 writes it. *)
let is_token_byte = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`' | '|' | '~' -> true
  | _ -> false

(* Is this a header line with its colon at this position? A name with a space, a folded line or a lone line end could be
   read otherwise by a proxy in front: that is how a second request gets smuggled in. In one pass, because every header
   of every request comes through here. *)
let is_header ctx (a : Types.t array) =
  let line = Native.text_arg ctx "is_header" a.(1) in
  match a.(0) with
  | Int at when at >= 0 && at <= String.length line ->
    Runtime.pay_bytes ctx (String.length line);
    let rec clean i =
      i >= String.length line
      || (let c = line.[i] in
          c <> '\r' && c <> '\n' && (i >= at || is_token_byte c) && clean (i + 1))
    in
    Value.of_bool (at > 0 && clean 0)
  | v -> Runtime.fail ctx Type (Messages.need_size "is_header" (Value.describe v))

let natives n =
  [ "listen", Native.nat ~params:[| "port"; "host" |] "listen" 1 2 (listen n);
    "accept", Native.nat "accept" 1 1 (accept n);
    "connect", Native.nat "connect" 2 2 (connect n);
    "read", Native.nat "read" 1 1 (read n);
    "write", Native.nat "write" 2 2 (write n);
    "close", Native.nat "close" 1 1 (close n);
    "arm", Native.nat "arm" 2 2 (arm n);
    "reap", Native.nat "reap" 0 0 (reap n);
    "find", Native.nat "find" 2 2 find;
    "split_at", Native.nat "split_at" 2 2 split_at;
    "is_header", Native.nat "is_header" 2 2 is_header;
    "size", Native.nat "size" 1 1 (fun ctx a -> Int (String.length (Native.text_arg ctx "size" a.(0))));
    "open_count", Native.nat "open_count" 0 0 (fun _ _ -> Int (Hashtbl.length n.sockets)) ]
