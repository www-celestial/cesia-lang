open Kepler
open Types

let chunk_size = 65536

let text_list ctx (v : t) =
  match v with
  | Undef -> [||]
  | Array x -> Array.init (x.rows * x.cols) (fun k -> Native.text_arg ctx "run" (Value.elt x k))
  | _ -> Runtime.fail ctx Type (Messages.need_array "run" (Value.describe v))

(* A stream of the command, while it is open. *)
type pipe = { fd : Unix.file_descr; mutable live : bool }

let finish poll p =
  if p.live then begin
    p.live <- false;
    Poll.forget poll p.fd;
    Unix.close p.fd
  end

(* Reads what is there. Says whether anything happened. *)
let drain ctx poll p buffer chunk =
  if not p.live then false
  else
    match Unix.read p.fd chunk 0 chunk_size with
    | 0 -> finish poll p; true
    | n ->
      Runtime.reserve ctx ((n / 8) + 1);
      Buffer.add_subbytes buffer chunk 0 n;
      true
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> false

(* Writes what the pipe takes. A command that stops reading just ends the input. *)
let feed poll p input at =
  if not p.live then false
  else if !at >= String.length input then (finish poll p; true)
  else
    match Unix.write_substring p.fd input !at (min chunk_size (String.length input - !at)) with
    | n -> at := !at + n; true
    | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR), _, _) -> false
    | exception Unix.Unix_error (Unix.EPIPE, _, _) -> finish poll p; true

(* Feeds the input and drains both outputs together: a command can fill one pipe while we wait on another. *)
let exchange ctx poll stdin_pipe stdout_pipe stderr_pipe input =
  let out = Buffer.create 256 and err = Buffer.create 256 in
  let chunk = Bytes.create chunk_size and at = ref 0 in
  let rec go () =
    let wrote = feed poll stdin_pipe input at in
    let read_out = drain ctx poll stdout_pipe out chunk in
    let read_err = drain ctx poll stderr_pipe err chunk in
    if stdout_pipe.live || stderr_pipe.live || stdin_pipe.live then begin
      if not (wrote || read_out || read_err) then begin
        let open_fds = List.filter_map (fun p -> if p.live then Some p.fd else None) in
        Poll.any_ready poll ctx ~read:(open_fds [ stdout_pipe; stderr_pipe ]) ~write:(open_fds [ stdin_pipe ])
      end;
      go ()
    end
  in
  go ();
  Buffer.contents out, Buffer.contents err

(* A child that closed its pipes may live on: other fibers run meanwhile. *)
let rec exit_code ctx poll pid pause =
  match Unix.waitpid [ Unix.WNOHANG ] pid with
  | 0, _ ->
    Poll.sleep poll ctx pause;
    exit_code ctx poll pid (Float.min 0.05 (pause *. 2.))
  | _, Unix.WEXITED code -> code
  | _, (Unix.WSIGNALED _ | Unix.WSTOPPED _) -> -1
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> exit_code ctx poll pid pause
  | exception Unix.Unix_error (Unix.ECHILD, _, _) -> -1  (* our parent told the system to ignore children *)

(* Three pipes, or nothing: descriptors can run out on any of them. *)
let rec pipes count =
  if count = 0 then []
  else begin
    let read, write = Unix.pipe ~cloexec:true () in
    match pipes (count - 1) with
    | rest -> (read, write) :: rest
    | exception (Unix.Unix_error _ as e) ->
      Unix.close read;
      Unix.close write;
      raise e
  end

(* SIGPIPE is ignored here, so that a command that stops reading is an EPIPE. The command itself gets the default. *)
let start cmd argv child_in child_out child_err =
  Sys.set_signal Sys.sigpipe Sys.Signal_default;
  Fun.protect
    ~finally:(fun () -> Sys.set_signal Sys.sigpipe Sys.Signal_ignore)
    (fun () -> Unix.create_process cmd argv child_in child_out child_err)

let run poll ctx (a : t array) =
  let w = ctx.w in
  let cmd = Native.text_arg ctx "run" a.(0) in
  Runtime.check_perm ctx Exec (Some cmd);
  let arg k = if Array.length a > k then a.(k) else Undef in
  let args = text_list ctx (arg 1) in
  let input = match arg 2 with Undef -> "" | v -> Native.text_arg ctx "run" v in
  let failed e = Fs.io_error w (Messages.io_failure "run" cmd (Fs.reason e)).text in
  match pipes 3 with
  | exception Unix.Unix_error (e, _, _) -> failed e
  | [ (in_read, in_write); (out_read, out_write); (err_read, err_write) ] ->
    let close_child () = List.iter Unix.close [ in_read; out_write; err_write ] in
    (match start cmd (Array.append [| cmd |] args) in_read out_write err_write with
     | exception Unix.Unix_error (e, _, _) ->
       close_child ();
       List.iter Unix.close [ in_write; out_read; err_read ];
       failed e
     | pid ->
       close_child ();
       let open_pipe fd =
         Poll.watch poll fd;
         { fd; live = true }
       in
       let stdin_pipe = open_pipe in_write and stdout_pipe = open_pipe out_read and stderr_pipe = open_pipe err_read in
       let out, err = exchange ctx poll stdin_pipe stdout_pipe stderr_pipe input in
       let code = exit_code ctx poll pid 0.0005 in
       let shape = Value.shape_of w [| "code"; "out"; "err" |] in
       Value.ok w (Struct { shape; fields = [| Int code; Text out; Text err |]; r_owned = true }))
  | _ -> assert false

let natives poll = [ "run", Native.nat ~params:[| "cmd"; "args"; "input" |] "run" 1 3 (run poll) ]
