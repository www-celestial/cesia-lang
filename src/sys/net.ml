open Cesia
open Types

type t = {
  poll : Poll.t;
  sockets : (int, Unix.file_descr) Hashtbl.t;
  deadlines : (int, float) Hashtbl.t;  (* arm of std/http: when a socket gets closed *)
  held : (int, int) Hashtbl.t;  (* hold of std/http: the bytes of the bodies each socket is reading *)
  mutable held_total : int;
  buffer : Bytes.t;  (* shared by reads: nothing suspends between a read and copying its bytes *)
  mutable stopping : bool;
  mutable handlers : bool;
  mutable windows : int;  (* how many windows hear of the stop signals: see [take_stops] *)
  mutable unheard : bool;  (* a stop signal has come since a window last heard of one *)
  own : (int, Unix.inet_addr * int) Hashtbl.t;  (* the address and port of each open listener, by socket: what net=own reaches *)
}

let chunk_size = 65536
let exit_on_second_signal = 130

let create poll =
  { poll; sockets = Hashtbl.create 64; deadlines = Hashtbl.create 64; held = Hashtbl.create 64; held_total = 0;
    buffer = Bytes.create chunk_size; stopping = false;
    handlers = false; windows = 0; unheard = false; own = Hashtbl.create 8 }

let stopping n = n.stopping

(* The first stop signal asks accept to end; the second one doesn't wait. With a window open, no signal cuts the program
   short: it hears of them and decides, as it may have a question to ask, and two can come at once from timeout and
   cesia do. *)
let catch_stops n =
  if not n.handlers then begin
    n.handlers <- true;
    let stop =
      Sys.Signal_handle
        (fun _ ->
           if n.stopping && n.windows = 0 then exit exit_on_second_signal;
           n.stopping <- true;
           n.unheard <- true;
           Poll.interrupt n.poll)
    in
    Sys.set_signal Sys.sigint stop;
    Sys.set_signal Sys.sigterm stop
  end

let install_handlers n =
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  catch_stops n

let take_stops n taken =
  if taken then catch_stops n;
  n.windows <- max 0 (n.windows + if taken then 1 else -1)

let stop_asked n =
  let asked = n.windows > 0 && n.unheard in
  if asked then n.unheard <- false;
  asked

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

let resolver = ref (fun host -> (Unix.gethostbyname host).Unix.h_addr_list.(0))

(* The fiber waits on a pipe that the domain closes when it has the answer. With no domain left, it asks by itself. *)
let looked_up n ctx host =
  let resolve = !resolver in
  let reader, writer = Unix.pipe ~cloexec:true () in
  let answer = Atomic.make None in
  let work () =
    let found =
      match resolve host with
      | addr -> Some addr
      | exception (Not_found | Invalid_argument _) -> None
    in
    Atomic.set answer (Some found);
    Unix.close writer
  in
  match Domain.spawn work with
  | exception Failure _ ->
    Unix.close reader;
    Unix.close writer;
    resolve host
  | domain ->
    Poll.watch n.poll reader;
    while Atomic.get answer = None do
      Poll.read_ready n.poll ctx reader
    done;
    Poll.forget n.poll reader;
    Unix.close reader;
    Domain.join domain;
    (match Atomic.get answer with
     | Some (Some addr) -> addr
     | _ -> raise Not_found)

(* An address written out, or localhost: what needs no lookup. *)
let literal host =
  if host = "localhost" then Some Unix.inet_addr_loopback
  else match Unix.inet_addr_of_string host with a -> Some a | exception Failure _ -> None

let address n ctx host = match literal host with Some a -> a | None -> looked_up n ctx host

let family addr = Unix.domain_of_sockaddr (Unix.ADDR_INET (addr, 0))

(* An address of this machine only: 127.0.0.0/8 or ::1. *)
let is_loopback addr =
  if family addr = Unix.PF_INET6 then addr = Unix.inet6_addr_loopback
  else String.starts_with ~prefix:"127." (Unix.string_of_inet_addr addr)

(* Is a listener of this program open at this loopback address and port? One on every address of its family counts too. *)
let is_own n addr port =
  let any = if family addr = Unix.PF_INET6 then Unix.inet6_addr_any else Unix.inet_addr_any in
  Hashtbl.fold (fun _ (a, p) found -> found || (p = port && (a = addr || a = any))) n.own false

(* The address to listen on, checked: the one bound is the one checked, with no second lookup. net=:PORT listens on this
   machine only, on the address a name resolves to when it is of this machine; net=own looks up no name. Other machines
   reach any other address, so it needs its own grant: net=0.0.0.0:8080, net=[::]:8080, or the address of one interface. *)
let listen_address n ctx host port target =
  if Runtime.granted ctx.w Net (Some target) then address n ctx host
  else
    let here = Printf.sprintf ":%d" port in
    let addr =
      if Runtime.granted ctx.w Net (Some here) then address n ctx host
      else
        match literal host with
        | Some a when is_loopback a && Runtime.granted ctx.w Net (Some "own") -> a
        | Some a when is_loopback a -> Runtime.check_perm ctx Net (Some here); a
        | Some a -> a
        | None -> Runtime.fail ctx Permission (Messages.denied "net" (Some target))
    in
    if is_loopback addr then addr else Runtime.fail ctx Permission (Messages.listen_denied target port)

let listen n ctx (a : Types.t array) =
  let port = port_arg ctx a.(0) in
  let host = if Array.length a > 1 && a.(1) != Undef then Native.text_arg ctx "Listen" a.(1) else "127.0.0.1" in
  let target = Printf.sprintf "%s:%d" (if String.contains host ':' then "[" ^ host ^ "]" else host) port in
  match listen_address n ctx host port target with
  | exception Not_found -> Fs.io_error ctx.w (Messages.io_failure "find" host "unknown host").text
  | addr ->
    install_handlers n;
    match
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
    | fd ->
      let socket = handle n ctx fd in
      (match socket, Unix.getsockname fd with
       | Handle { id; _ }, Unix.ADDR_INET (a, p) -> Hashtbl.replace n.own id (a, p)
       | _ -> ());
      Value.ok ctx.w socket
    | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "listen on" target e

let accept n ctx (a : Types.t array) =
  with_socket n ctx "Accept" a.(0) (fun fd ->
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
            if Hashtbl.mem n.sockets (socket_arg ctx "Accept" a.(0)) then go () else closed ctx
          | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "accept on" "this socket" e
      in
      go ())

let connect n ctx (a : Types.t array) =
  let host = Native.text_arg ctx "Connect" a.(0) and port = port_arg ctx a.(1) in
  let target = Printf.sprintf "%s:%d" host port in
  (* net=own reaches the listeners of this program only, while they are open, at an address written out or localhost: it
     looks up no name, since a lookup would already say something to the outside. *)
  let chosen =
    if Runtime.granted ctx.w Net (Some target) then None
    else if Runtime.granted ctx.w Net (Some "own") then begin
      match literal host with
      | Some addr when is_loopback addr && is_own n addr port -> Some addr
      | _ -> Runtime.fail ctx Permission (Messages.not_own target)
    end
    else (Runtime.check_perm ctx Net (Some target); None)
  in
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  match (match chosen with Some addr -> addr | None -> address n ctx host) with
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
  let id = socket_arg ctx "Read" a.(0) in
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
  let id = socket_arg ctx "Write" a.(0) in
  let text = Native.text_arg ctx "Write" a.(1) in
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

let release n id =
  match Hashtbl.find_opt n.held id with
  | Some bytes ->
    Hashtbl.remove n.held id;
    n.held_total <- n.held_total - bytes
  | None -> ()

let close_socket n id =
  release n id;
  Hashtbl.remove n.deadlines id;
  Hashtbl.remove n.own id;
  match Hashtbl.find_opt n.sockets id with
  | None -> ()
  | Some fd ->
    Hashtbl.remove n.sockets id;
    Poll.forget n.poll fd;
    Unix.close fd

let close n ctx (a : Types.t array) =
  close_socket n (socket_arg ctx "Close" a.(0));
  Missing

(* A socket that outlives its deadline is closed by reap, which wakes whoever waits on it: a slow client can't hold a fiber
   forever. 0 removes the deadline, while a handler runs. Another deadline starts the time of the next request: what the
   last one held, by hold, is released. *)
let arm n ctx (a : Types.t array) =
  let id = socket_arg ctx "arm" a.(0) in
  let seconds = match a.(1) with
    | Int i -> float_of_int i
    | Float x -> x
    | v -> Runtime.fail ctx Type (Messages.need_number "arm" (Value.describe v))
  in
  if seconds <= 0. then Hashtbl.remove n.deadlines id
  else if Hashtbl.mem n.sockets id then begin
    release n id;
    Hashtbl.replace n.deadlines id (Unix.gettimeofday () +. seconds)
  end;
  Missing

(* The bodies that std/http reads at once take at most a quarter of the memory limit: past it, a request gets a 503 at
   once, and the server lives on, where reading them all would reach the limit. A socket holds what it reads until it
   holds 0 again, or closes. *)
let hold n ctx (a : Types.t array) : Types.t =
  let id = socket_arg ctx "hold" a.(0) in
  let bytes = match a.(1) with Int b when b >= 0 -> b | v -> Runtime.fail ctx Type (Messages.need_count "hold" (Value.describe v)) in
  release n id;
  let most = ctx.w.limits.memory_words in
  let budget = if most = max_int then max_int else most * 2 in
  if bytes = 0 then True
  else if bytes > budget - n.held_total then False
  else begin
    Hashtbl.replace n.held id bytes;
    n.held_total <- n.held_total + bytes;
    True
  end

let reap n _ _ : Types.t =
  let now = Unix.gettimeofday () in
  let late = Hashtbl.fold (fun id t acc -> if t <= now then id :: acc else acc) n.deadlines [] in
  List.iter (close_socket n) late;
  Int (List.length late)

(* A header name, as RFC 9110 writes it. *)
let is_token_byte = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`' | '|' | '~' -> true
  | _ -> false

(* Is this a header line with its colon at this position? A name with a space, a folded line or a lone line end could be
   read otherwise by a proxy in front: that is how a second request gets smuggled in. In one pass, because every header
   of every request comes through here. *)
let header_ok line at =
  let rec clean i =
    i >= String.length line
    || (let c = line.[i] in
        c <> '\r' && c <> '\n' && (i >= at || is_token_byte c) && clean (i + 1))
  in
  at > 0 && clean 0

let is_header ctx (a : Types.t array) =
  let line = Native.text_arg ctx "isHeader" a.(1) in
  match a.(0) with
  | Int at when at >= 0 && at <= String.length line ->
    Runtime.pay_bytes ctx (String.length line);
    Value.of_bool (header_ok line at)
  | v -> Runtime.fail ctx Type (Messages.need_size "isHeader" (Value.describe v))

let header_keys = Trie.names [| "Name"; "Value" |]
let request_keys = Trie.names [| "Method"; "Path"; "Query"; "Headers"; "Body" |]
let parsed_keys = Trie.names [| "Request"; "Rest"; "Close" |]
let needs_keys = Trie.names [| "Needs" |]

(* Where part first starts in s between from and until, or -1. *)
let find part s from until =
  let m = String.length part in
  let rec at i k = k = m || (s.[i + k] = part.[k] && at i (k + 1)) in
  let rec go i = if i + m > until then -1 else if at i 0 then i else go (i + 1) in
  go from

let line_end s from until = find "\r\n" s from until

(* The first request of a buffer, in one pass, since every request comes through here: Ok(missing) if its head isn't all
   there, Ok({Needs}) with the size of the whole request if its body isn't, Ok({Request, Rest, Close}), or Err of the
   status that refuses it. Its line holds three words between single spaces and no line end; each header line holds a
   name, as is_header checks it, and its value, trimmed. A body comes with one content-length, of digits, no larger than
   [limit]; transfer-encoding is not implemented. Close says that the connection ends after it, as asked by HTTP/1.0 or by
   connection: close. *)
let request ctx (a : Types.t array) : Types.t =
  let s = Native.text_arg ctx "request" a.(0) in
  let int k = match a.(k) with Int i -> i | v -> Runtime.fail ctx Type (Messages.need_count "request" (Value.describe v)) in
  let limit = int 1 and most = int 2 in
  let fail status = Value.err ctx.w (Int status) in
  let at = find "\r\n\r\n" s 0 (String.length s) in
  Runtime.pay_bytes ctx (if at < 0 then String.length s else at);
  if at < 0 then if String.length s > most then fail 431 else Value.ok ctx.w Missing
  else if at > most then fail 431
  else
    let first = match line_end s 0 at with -1 -> at | e -> e in
    let line = String.sub s 0 first in
    match String.split_on_char ' ' line with
    | [ meth; target; version ]
      when meth <> "" && target <> "" && (version = "HTTP/1.1" || version = "HTTP/1.0")
           && not (String.contains line '\r' || String.contains line '\n') ->
      let rec headers from acc =
        if from >= at then Some (List.rev acc)
        else
          let stop = match line_end s from at with -1 -> at | e -> e in
          let l = String.sub s from (stop - from) in
          match String.index_opt l ':' with
          | Some colon when header_ok l colon ->
            let name = String.lowercase_ascii (String.sub l 0 colon) in
            let v = String.trim (String.sub l (colon + 1) (String.length l - colon - 1)) in
            headers (stop + 2) ((name, v) :: acc)
          | _ -> None
      in
      (match headers (first + 2) [] with
       | None -> fail 400
       | Some hs ->
         let named n = List.filter_map (fun (k, v) -> if k = n then Some v else None) hs in
         let digits v = v <> "" && String.length v <= 18 && String.for_all (fun c -> c >= '0' && c <= '9') v in
         let size = match named "content-length" with [] -> Some 0 | [ v ] when digits v -> Some (int_of_string v) | _ -> None in
         let body_at = at + 4 in
         if named "transfer-encoding" <> [] then fail 501
         else
           match size with
           | None -> fail 400
           | Some n when n > limit -> fail 413
           | Some n when String.length s - body_at < n -> Value.ok ctx.w (Trie.record needs_keys [| Int (body_at + n) |])
           | Some n ->
             let path, query =
               match String.index_opt target '?' with
               | Some q -> String.sub target 0 q, String.sub target (q + 1) (String.length target - q - 1)
               | None -> target, ""
             in
             let items = Array.of_list (List.map (fun (k, v) -> Trie.record header_keys [| Text k; Text v |]) hs) in
             let list = Types.Array { rows = 1; cols = Array.length items; store = V items; a_owned = true; a_tip = true; dims = [||] } in
             Runtime.build ctx ((String.length s / 4) + (8 * Array.length items) + 32);
             let body = String.sub s body_at n and rest = String.sub s (body_at + n) (String.length s - body_at - n) in
             let close = version = "HTTP/1.0" || (match named "connection" with v :: _ -> String.lowercase_ascii v = "close" | [] -> false) in
             let req = Trie.record request_keys [| Text meth; Text path; Text query; list; Text body |] in
             Value.ok ctx.w (Trie.record parsed_keys [| req; Text rest; Value.of_bool close |]))
    | _ -> fail 400

(* The port a socket is bound to: the one the system chose for a Listen on port 0. *)
let port n ctx (a : Types.t array) =
  with_socket n ctx "Port" a.(0) (fun fd ->
      match Unix.getsockname fd with
      | Unix.ADDR_INET (_, p) -> Int p
      | _ -> Missing)

let reset n =
  Hashtbl.iter (fun _ fd -> Poll.forget n.poll fd; (try Unix.close fd with Unix.Unix_error _ -> ())) n.sockets;
  Hashtbl.reset n.sockets;
  Hashtbl.reset n.deadlines;
  Hashtbl.reset n.held;
  n.held_total <- 0;
  Hashtbl.reset n.own

let natives n =
  [ "Listen", Native.nat ~result:true ~params:[| "port"; "host" |] "Listen" 1 2 (listen n);
    "Port", Native.nat "Port" 1 1 (port n);
    "Accept", Native.nat ~result:true "Accept" 1 1 (accept n);
    "Connect", Native.nat ~result:true "Connect" 2 2 (connect n);
    "Read", Native.nat ~result:true "Read" 1 1 (read n);
    "Write", Native.nat ~result:true "Write" 2 2 (write n);
    "Close", Native.nat "Close" 1 1 (close n) ]

(* The parts of a path between its slashes, the empty ones left out: "/notes//12/" gives notes and 12. In one pass, because
   every request is routed through here. *)
let segments ctx (a : Types.t array) =
  let path = Native.text_arg ctx "segments" a.(0) in
  Runtime.build ctx ((String.length path / 8) + 1);
  let parts = List.filter (fun p -> p <> "") (String.split_on_char '/' path) in
  let items = Array.of_list (List.map (fun p -> Types.Text p) parts) in
  Types.Array { rows = 1; cols = Array.length items; store = V items; a_owned = true; a_tip = true; dims = [||] }

(* Small names: only the files of std/http see them, which keep the deadlines of the connections they serve. *)
let http_natives n =
  [ "arm", Native.nat "arm" 2 2 (arm n);
    "hold", Native.nat "hold" 2 2 (hold n);
    "reap", Native.nat "reap" 0 0 (reap n);
    "isHeader", Native.nat "isHeader" 2 2 is_header;
    "request", Native.nat "request" 3 3 request;
    "segments", Native.nat "segments" 1 1 segments;
    "openCount", Native.nat "openCount" 0 0 (fun _ _ -> Int (Hashtbl.length n.sockets)) ]
