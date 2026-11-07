(* cesia run --workers N. The first process runs the program up to its first listener, opens it, and becomes the
   supervisor: it starts N workers, each a cesia run of the same program with that listener as its standard input, and
   never serves itself. The workers take their connections from the one queue of the listener, which the supervisor keeps
   open, so that a worker can stop without a connection lost. The supervisor starts again a worker that ends, stops them
   all on TERM or INT, and replaces them on HUP: the new ones start from the files as they are now, say that they
   accept, and only then do the old ones get TERM, after which each ends its requests in progress. Each worker leads a
   process group of its own: a terminal's signals reach the supervisor alone, which decides. *)
open Cesia

external spawn_group : string -> string array -> Unix.file_descr array -> int = "cesia_spawn_group"

(* The variable that makes a cesia run a worker: the path of the supervisor's socket, the port and the host. *)
let variable = "CESIA_WORKER"

type worker = {
  pid : int;
  generation : int;
  started : float;
  mutable ready : bool;
  mutable control : Unix.file_descr option;  (* the worker's connection: it ends when the supervisor does *)
}

(* A worker that ends sooner than this after its start comes back after a pause, which doubles each time. *)
let short_life = 1.
let longest_pause = 30.

(* How long new workers have to accept, on HUP, before the supervisor gives up and keeps the running ones. *)
let reload_wait = 30.

(* The workers share their standard output: a write of at most 4096 bytes (PIPE_BUF) that ends a line can't be cut by
   another worker's, into a pipe as into a file. *)
let write_lines s =
  let n = String.length s in
  let rec go from =
    if from < n then begin
      let stop =
        if n - from <= 4096 then n
        else match String.rindex_from_opt s (from + 4095) '\n' with Some k when k >= from -> k + 1 | _ -> from + 4096
      in
      print_string (String.sub s from (stop - from));
      flush stdout;
      go stop
    end
  in
  go 0

let say (m : Messages.t) = prerr_endline ("cesia: " ^ m.text)
let code_of = function Unix.WEXITED c -> c | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 1

(* A folder only this user reads, for the socket. *)
let private_dir () =
  let base = Filename.get_temp_dir_name () in
  let rec make tries =
    let dir = Filename.concat base (Printf.sprintf "cesia-workers-%d-%06x" (Unix.getpid ()) (Random.bits () land 0xFFFFFF)) in
    match Unix.mkdir dir 0o700 with
    | () -> dir
    | exception Unix.Unix_error (Unix.EEXIST, _, _) when tries > 0 -> make (tries - 1)
  in
  Random.self_init ();
  make 10

let supervise ~count ~argv ~listener ~host ~port : 'a =
  let dir = private_dir () in
  let path = Filename.concat dir "control" in
  let control = Unix.socket ~cloexec:true Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.bind control (Unix.ADDR_UNIX path);
  Unix.listen control 64;
  Unix.set_nonblock control;
  Unix.putenv variable (Printf.sprintf "%s %d %s" path port host);
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let workers : (int, worker) Hashtbl.t = Hashtbl.create 16 in
  let unknown = ref [] in  (* connections that haven't said which worker they are *)
  let current = ref 0 and next = ref None and asked = ref 0 and reload = ref false in
  let pause = ref 0.1 and later = ref [] and failed = ref 0 and first_ready = ref false in
  let cleanup () =
    (try Unix.unlink path with Unix.Unix_error _ -> ());
    try Unix.rmdir dir with Unix.Unix_error _ -> ()
  in
  let signal_all s = Hashtbl.iter (fun pid _ -> try Unix.kill pid s with Unix.Unix_error _ -> ()) workers in
  let in_generation g = Hashtbl.fold (fun _ w acc -> if w.generation = g then w :: acc else acc) workers [] in
  let start generation =
    let pid = spawn_group argv.(0) argv [| listener; Unix.stdout; Unix.stderr |] in
    Hashtbl.replace workers pid { pid; generation; started = Unix.gettimeofday (); ready = false; control = None }
  in
  let stop_signal = Sys.Signal_handle (fun s ->
      incr asked;
      if !asked = 1 then signal_all Sys.sigterm
      else begin
        signal_all Sys.sigkill;
        cleanup ();
        exit (128 + if s = Sys.sigterm then 15 else 2)
      end)
  in
  Sys.set_signal Sys.sigterm stop_signal;
  Sys.set_signal Sys.sigint stop_signal;
  Sys.set_signal Sys.sighup (Sys.Signal_handle (fun _ -> reload := true));
  for _ = 1 to count do start 0 done;
  (* A new generation that can't start leaves the running one alone. *)
  let give_up (m : Messages.t) =
    Option.iter (fun (g, _) -> List.iter (fun w -> try Unix.kill w.pid Sys.sigterm with Unix.Unix_error _ -> ()) (in_generation g)) !next;
    next := None;
    say m
  in
  let ended pid status =
    match Hashtbl.find_opt workers pid with
    | None -> ()
    | Some w ->
      Hashtbl.remove workers pid;
      Option.iter Unix.close w.control;
      let code = code_of status in
      if !asked > 0 then (if code <> 0 && !failed = 0 then failed := code)
      else if (match !next with Some (g, _) -> w.generation = g | None -> false) then give_up (Messages.workers_new_ended code)
      else if w.generation = !current then begin
        if not !first_ready && not w.ready then begin
          (* The program can't start: no use starting it again. *)
          say (Messages.workers_cant_start code);
          failed := code;
          incr asked;
          signal_all Sys.sigterm
        end
        else begin
          say (Messages.workers_ended pid code);
          let now = Unix.gettimeofday () in
          if now -. w.started < short_life then begin
            later := (now +. !pause, w.generation) :: !later;
            pause := Float.min longest_pause (!pause *. 2.)
          end
          else begin
            pause := 0.1;
            start w.generation
          end
        end
      end
  in
  let rec reap () =
    match Unix.waitpid [ Unix.WNOHANG ] (-1) with
    | 0, _ -> ()
    | pid, status -> ended pid status; reap ()
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> reap ()
    | exception Unix.Unix_error (Unix.ECHILD, _, _) -> ()
  in
  (* A worker says its number on its connection once it accepts. *)
  let heard fd =
    let bytes = Bytes.create 32 in
    match Unix.read fd bytes 0 32 with
    | exception Unix.Unix_error _ -> ()
    | got ->
      unknown := List.filter (fun u -> u != fd) !unknown;
      match int_of_string_opt (String.trim (Bytes.sub_string bytes 0 got)) with
      | Some pid when Hashtbl.mem workers pid ->
        let w = Hashtbl.find workers pid in
        w.ready <- true;
        w.control <- Some fd;
        if w.generation = 0 then first_ready := true;
        (match !next with
         | Some (g, _) when List.for_all (fun w -> w.ready) (in_generation g) && List.length (in_generation g) = count ->
           List.iter (fun w -> try Unix.kill w.pid Sys.sigterm with Unix.Unix_error _ -> ()) (in_generation !current);
           current := g;
           next := None
         | _ -> ())
      | _ -> Unix.close fd
  in
  let rec accept_all () =
    match Unix.accept ~cloexec:true control with
    | fd, _ -> unknown := fd :: !unknown; accept_all ()
    | exception Unix.Unix_error _ -> ()
  in
  while !asked = 0 || Hashtbl.length workers > 0 do
    reap ();
    let now = Unix.gettimeofday () in
    let due, waiting = List.partition (fun (at, _) -> at <= now) !later in
    later := waiting;
    if !asked = 0 then List.iter (fun (_, g) -> if g = !current then start g) due;
    if !reload && !asked = 0 then begin
      reload := false;
      if !next = None then begin
        let g = !current + 1 in
        next := Some (g, now +. reload_wait);
        for _ = 1 to count do start g done
      end
    end;
    (match !next with Some (_, deadline) when now > deadline -> give_up Messages.workers_new_late | _ -> ());
    match Unix.select (control :: !unknown) [] [] 0.05 with
    | ready, _, _ -> List.iter (fun fd -> if fd == control then accept_all () else heard fd) ready
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> ()
  done;
  cleanup ();
  exit !failed
