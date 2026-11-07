(* The load client of tools/http-bench.sh. Each connection sends a request as soon as the last answer has arrived, on one
   domain or several (--threads); with --new, each request goes on a connection of its own, which the server closes.
   It prints the requests per second, the median and the 99th percentile of the latency in milliseconds, and the
   failures: a connection refused, reset or closed before its answer, an answer that isn't a 200, or one that took more
   than 5 seconds. Each failed connection is opened again, and the client ends with 1 if any request failed. *)
open Cesia_sys

let slow = 5.

type conn = {
  mutable fd : Unix.file_descr option;
  data : Buffer.t;
  mutable sent : float;  (* when the request left, or when the connect began *)
  mutable connecting : bool;
  mutable retry_at : float;  (* a refused connection waits a little before the next try *)
}

type tally = { mutable ok : int; mutable failed : int; mutable latencies : Float.Array.t; mutable n : int }

let record t latency =
  if t.n = Float.Array.length t.latencies then begin
    let bigger = Float.Array.make (2 * t.n) 0. in
    Float.Array.blit t.latencies 0 bigger 0 t.n;
    t.latencies <- bigger
  end;
  Float.Array.set t.latencies t.n latency;
  t.n <- t.n + 1;
  t.ok <- t.ok + 1

(* The size of a whole response at the start of [s], once its head has arrived and says it; missing until then. *)
let rec find part s from =
  if from + String.length part > String.length s then None
  else if String.sub s from (String.length part) = part then Some from
  else find part s (from + 1)

let response_size s =
  match find "\r\n\r\n" s 0 with
  | None -> None
  | Some at ->
    let head = String.lowercase_ascii (String.sub s 0 at) in
    let closing = find "\r\nconnection: close" head 0 <> None in
    let length =
      match find "content-length:" head 0 with
      | None -> 0
      | Some k ->
        let rec digits i n = if i < at && head.[i] = ' ' && n = 0 then digits (i + 1) n
          else if i < at && head.[i] >= '0' && head.[i] <= '9' then digits (i + 1) ((n * 10) + Char.code head.[i] - 48)
          else n in
        digits (k + 15) 0
    in
    Some (at + 4 + length, closing)

let status s = match String.split_on_char ' ' s with _ :: code :: _ -> int_of_string_opt code | _ -> None

let worker ~port ~path ~fresh ~connections ~stop =
  let request =
    Printf.sprintf "GET %s HTTP/1.1\r\nHost: bench\r\n%s\r\n" path (if fresh then "Connection: close\r\n" else "")
  in
  let backend = Backend.create () in
  let by_fd = Hashtbl.create (2 * connections) in
  let tally = { ok = 0; failed = 0; latencies = Float.Array.make 4096 0.; n = 0 } in
  let chunk = Bytes.create 65536 in
  let drop c =
    Option.iter
      (fun fd ->
         Hashtbl.remove by_fd fd;
         Backend.remove backend fd;
         Unix.close fd)
      c.fd;
    c.fd <- None
  in
  let send c fd =
    c.sent <- Unix.gettimeofday ();
    match Unix.write_substring fd request 0 (String.length request) with
    | _ -> ()
    | exception Unix.Unix_error _ -> ()  (* the read that follows tells *)
  in
  let opened c =
    let fd = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
    Unix.set_nonblock fd;
    Unix.setsockopt fd Unix.TCP_NODELAY true;
    Buffer.clear c.data;
    c.fd <- Some fd;
    c.sent <- Unix.gettimeofday ();
    Hashtbl.replace by_fd fd c;
    Backend.add backend fd;
    match Unix.connect fd (Unix.ADDR_INET (Unix.inet_addr_loopback, port)) with
    | () -> c.connecting <- false; send c fd
    | exception Unix.Unix_error (Unix.EINPROGRESS, _, _) -> c.connecting <- true
    | exception Unix.Unix_error _ ->
      tally.failed <- tally.failed + 1;
      drop c;
      c.retry_at <- Unix.gettimeofday () +. 0.01
  in
  let fail c =
    tally.failed <- tally.failed + 1;
    drop c;
    opened c
  in
  (* A whole response: counted, then the next request, on this connection or on a new one: a server that stops says that it
     closes the connection, which is no failure. *)
  let answered c fd size closing =
    let s = Buffer.contents c.data in
    (match status s with Some 200 -> record tally (Unix.gettimeofday () -. c.sent) | _ -> tally.failed <- tally.failed + 1);
    Buffer.clear c.data;
    Buffer.add_string c.data (String.sub s size (String.length s - size));
    if fresh || closing then (drop c; opened c) else send c fd
  in
  let rec drain c fd =
    match Unix.read fd chunk 0 (Bytes.length chunk) with
    | 0 -> fail c
    | got ->
      Buffer.add_subbytes c.data chunk 0 got;
      (match response_size (Buffer.contents c.data) with
       | Some (size, closing) when Buffer.length c.data >= size -> answered c fd size closing
       | _ -> drain c fd)
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
    | exception Unix.Unix_error _ -> fail c
  in
  let ready fd =
    match Hashtbl.find_opt by_fd fd with
    | None -> ()
    | Some c when c.connecting ->
      (match Unix.getsockopt_error fd with
       | None -> c.connecting <- false; send c fd; drain c fd
       | Some _ -> tally.failed <- tally.failed + 1; drop c; c.retry_at <- Unix.gettimeofday () +. 0.01)
    | Some c -> drain c fd
  in
  let conns = Array.init connections (fun _ ->
      { fd = None; data = Buffer.create 256; sent = 0.; connecting = false; retry_at = 0. }) in
  Array.iter opened conns;
  let last_check = ref (Unix.gettimeofday ()) in
  while Unix.gettimeofday () < stop do
    List.iter ready (Backend.wait backend 0.01 (fun () -> [], []));
    let now = Unix.gettimeofday () in
    if now -. !last_check > 0.05 then begin
      last_check := now;
      Array.iter
        (fun c ->
           match c.fd with
           | None -> if now >= c.retry_at then opened c
           | Some _ -> if now -. c.sent > slow then fail c)
        conns
    end
  done;
  Array.iter drop conns;
  tally

let () =
  let port = ref 19100 and connections = ref 100 and idle = ref 0 and seconds = ref 3. and path = ref "/" in
  let fresh = ref false and threads = ref 1 in
  Arg.parse
    [ "--port", Arg.Set_int port, "port";
      "--connections", Arg.Set_int connections, "active connections";
      "--idle", Arg.Set_int idle, "idle connections, open all along";
      "--seconds", Arg.Set_float seconds, "duration";
      "--path", Arg.Set_string path, "the path asked";
      "--new", Arg.Set fresh, "a new connection for each request";
      "--threads", Arg.Set_int threads, "domains that send requests" ]
    (fun _ -> ())
    "http_load";
  let kept =
    List.init !idle (fun _ ->
        let s = Unix.socket ~cloexec:true Unix.PF_INET Unix.SOCK_STREAM 0 in
        Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, !port));
        s)
  in
  let threads = max 1 (min !threads !connections) in
  let start = Unix.gettimeofday () in
  let stop = start +. !seconds in
  let share k = (!connections / threads) + if k < !connections mod threads then 1 else 0 in
  let run k () = worker ~port:!port ~path:!path ~fresh:!fresh ~connections:(share k) ~stop in
  let others = List.init (threads - 1) (fun k -> Domain.spawn (run (k + 1))) in
  let first = run 0 () in
  let tallies = first :: List.map Domain.join others in
  let elapsed = Unix.gettimeofday () -. start in
  List.iter Unix.close kept;
  let ok = List.fold_left (fun a t -> a + t.ok) 0 tallies and failed = List.fold_left (fun a t -> a + t.failed) 0 tallies in
  let all = Float.Array.concat (List.map (fun t -> Float.Array.sub t.latencies 0 t.n) tallies) in
  Float.Array.sort compare all;
  let at q = if ok = 0 then 0. else 1000. *. Float.Array.get all (min (ok - 1) (int_of_float (q *. float_of_int ok))) in
  Printf.printf "%d %.3f %.3f %d\n" (int_of_float (float_of_int ok /. elapsed)) (at 0.5) (at 0.99) failed;
  exit (if failed > 0 then 1 else 0)
