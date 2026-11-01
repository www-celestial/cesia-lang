(* The load client: keep-alive connections that each send a request as soon as the last answer arrives. *)
open Kepler_sys

let request = "GET / HTTP/1.1\r\nHost: bench\r\n\r\n"

let connect port =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.setsockopt s Unix.TCP_NODELAY true;
  s

let send fd = ignore (Unix.write_substring fd request 0 (String.length request))

let () =
  let port = ref 19100 and connections = ref 100 and idle = ref 0 and seconds = ref 3. in
  Arg.parse
    [ "--port", Arg.Set_int port, "port";
      "--connections", Arg.Set_int connections, "active connections";
      "--idle", Arg.Set_int idle, "idle connections";
      "--seconds", Arg.Set_float seconds, "duration" ]
    (fun _ -> ())
    "http_load";
  let kept = List.init !idle (fun _ -> connect !port) in
  let backend = Backend.create () in
  for _ = 1 to !connections do
    let fd = connect !port in
    Backend.add backend fd;
    send fd
  done;
  let buffer = Bytes.create 8192 and count = ref 0 in
  let start = Unix.gettimeofday () in
  let stop = start +. !seconds in
  while Unix.gettimeofday () < stop do
    let on_ready fd =
      match Unix.read fd buffer 0 8192 with
      | 0 -> failwith "the server closed a connection"
      | _ ->
        incr count;
        send fd
      | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> ()
    in
    List.iter on_ready (Backend.wait backend 0.2 (fun () -> [], []))
  done;
  ignore kept;
  Printf.printf "%d\n" (int_of_float (float_of_int !count /. (Unix.gettimeofday () -. start)))
