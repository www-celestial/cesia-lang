open Cesia
open Types

let chunk_size = 65536
let run_keys = Trie.names [| "Code"; "Out"; "Err" |]

let text_list ctx name (v : t) =
  match v with
  | Undef -> [||]
  | Array x -> Array.init (x.rows * x.cols) (fun k -> Native.text_arg ctx name (Value.elt x k))
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

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
    | exception Unix.Unix_error (e, _, _) when Fs.retry e -> false

(* Writes what the pipe takes. A command that stops reading just ends the input. *)
let feed poll p input at =
  if not p.live then false
  else if !at >= String.length input then (finish poll p; true)
  else
    match Unix.write_substring p.fd input !at (min chunk_size (String.length input - !at)) with
    | n -> at := !at + n; true
    | exception Unix.Unix_error (e, _, _) when Fs.retry e -> false
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

let seconds ctx name v =
  match v with
  | Int i when i >= 0 -> float_of_int i
  | Float x when x >= 0. && x < infinity -> x
  | _ -> Runtime.fail ctx Type (Messages.bad_duration name (Value.describe v))

external spawn_group : string -> string array -> Unix.file_descr array -> int = "cesia_spawn_group"

(* SIGPIPE is ignored here, so that a command that stops reading is an EPIPE. The command itself gets the default. A
   command starts where its parent is, so the parent goes into [dir] for that moment: fibers take turns, and no other domain
   reads a relative path. With [group], it leads a process group of its own, which [stop] kills whole, but on Windows. *)
let start ?(dir = "") ?(group = false) cmd argv child_in child_out child_err =
  Sys.set_signal Sys.sigpipe Sys.Signal_default;
  let here = if dir = "" then "" else Unix.getcwd () in
  Fun.protect
    ~finally:(fun () ->
        Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
        if here <> "" then Unix.chdir here)
    (fun () ->
       if dir <> "" then Unix.chdir dir;
       if group && not Sys.win32 then spawn_group cmd argv [| child_in; child_out; child_err |]
       else Unix.create_process cmd argv child_in child_out child_err)

(* A command named by its path is the one of this program's folder, which exec= names, whatever dir it runs in. *)
let program cmd =
  let named = String.contains cmd '/' || (Sys.win32 && String.contains cmd '\\') in
  if named && Filename.is_relative cmd then Filename.concat (Sys.getcwd ()) cmd else cmd

(* Why a command didn't start: the folder it was to run in, when there is none, else the command. *)
let start_failed ctx cmd dir e =
  if dir <> "" && not (Sys.file_exists dir) then Fs.failed ctx "run in" dir e else Fs.failed ctx "run" cmd e

(* Kills a command started by [start], and all its group started. *)
let stop ~group pid = try Unix.kill (if group && not Sys.win32 then -pid else pid) Sys.sigkill with Unix.Unix_error _ -> ()

let run poll ctx (a : t array) =
  let w = ctx.w in
  let cmd = Native.text_arg ctx "Run" a.(0) in
  Runtime.check_perm ctx Exec (Some cmd);
  let arg k = if Array.length a > k then a.(k) else Undef in
  let args = text_list ctx "Run" (arg 1) in
  let input = match arg 2 with Undef -> "" | v -> Native.text_arg ctx "Run" v in
  let dir = match arg 3 with Undef -> "" | v -> Native.text_arg ctx "Run" v in
  let timeout = match arg 4 with Undef -> 0. | v -> seconds ctx "Run" v in
  let failed = start_failed ctx cmd dir in
  match pipes 3 with
  | exception Unix.Unix_error (e, _, _) -> failed e
  | [ (in_read, in_write); (out_read, out_write); (err_read, err_write) ] ->
    let close_child () = List.iter Unix.close [ in_read; out_write; err_write ] in
    (* A command with a timeout leads a group: past its time, the children it started go with it, and with them the ends of
       the pipes they hold. Without one, Ctrl-C reaches it as it reaches this program. *)
    let group = timeout > 0. in
    (match start ~dir ~group (program cmd) (Array.append [| cmd |] args) in_read out_write err_write with
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
       (* Past its time the command is killed; once it is waited for, its number may go to another. *)
       let cancel = if timeout > 0. then Poll.timer poll timeout (fun () -> stop ~group pid) else ignore in
       let out, err = exchange ctx poll stdin_pipe stdout_pipe stderr_pipe input in
       let code = exit_code ctx poll pid 0.0005 in
       cancel ();
       Value.ok w (Trie.record run_keys [| Int code; Text out; Text err |]))
  | _ -> assert false

(* A process that lives on, for terminals and long builds. Its output and its errors arrive as one stream. *)
type process = { pid : int; input : pipe; output : pipe }

let start_process poll procs ctx (a : t array) : t =
  let w = ctx.w in
  let cmd = Native.text_arg ctx "Start" a.(0) in
  Runtime.check_perm ctx Exec (Some cmd);
  let args = text_list ctx "Start" (if Array.length a > 1 then a.(1) else Undef) in
  let dir = match if Array.length a > 2 then a.(2) else Undef with Undef -> "" | v -> Native.text_arg ctx "Start" v in
  let failed = start_failed ctx cmd dir in
  match pipes 2 with
  | exception Unix.Unix_error (e, _, _) -> failed e
  | [ (in_read, in_write); (out_read, out_write) ] ->
    let close_child () = List.iter Unix.close [ in_read; out_write ] in
    (match start ~dir (program cmd) (Array.append [| cmd |] args) in_read out_write out_write with
     | exception Unix.Unix_error (e, _, _) ->
       close_child ();
       List.iter Unix.close [ in_write; out_read ];
       failed e
     | pid ->
       close_child ();
       Poll.watch poll in_write;
       Poll.watch poll out_read;
       let id = w.sched.next_id in
       w.sched.next_id <- id + 1;
       Hashtbl.replace procs id { pid; input = { fd = in_write; live = true }; output = { fd = out_read; live = true } };
       Value.ok w (Handle { kind = "process"; id; task = None }))
  | _ -> assert false

let process_arg procs ctx name (v : t) =
  match v with
  | Handle { kind = "process"; id; _ } ->
    (match Hashtbl.find_opt procs id with
     | Some p -> id, p
     | None -> Runtime.fail ctx Type Messages.process_ended)
  | _ -> Runtime.fail ctx Type (Messages.need_process name (Value.describe v))

(* What the process wrote, as it comes. An empty text means that it closed its output. *)
let rec read_output poll procs ctx (a : t array) : t =
  let _, p = process_arg procs ctx "ReadOutput" a.(0) in
  if not p.output.live then Value.ok ctx.w (Text "")
  else begin
    let chunk = Bytes.create chunk_size in
    match Unix.read p.output.fd chunk 0 chunk_size with
    | 0 ->
      finish poll p.output;
      Value.ok ctx.w (Text "")
    | n -> Value.ok ctx.w (Text (Bytes.sub_string chunk 0 n))
    | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
      Poll.read_ready poll ctx p.output.fd;
      read_output poll procs ctx a
  end

let quit ctx (a : t array) : t =
  match a.(0) with
  | Int code when code >= 0 && code <= 255 -> raise (Value.Quit code)
  | v -> Runtime.fail ctx Type (Messages.exit_code (Value.describe v))

let write_input poll procs ctx (a : t array) : t =
  let _, p = process_arg procs ctx "WriteInput" a.(0) in
  let s = Native.text_arg ctx "WriteInput" a.(1) in
  let n = String.length s in
  let rec go at =
    if not p.input.live then Fs.io_error ctx.w Messages.input_closed.text
    else if at >= n then Value.ok ctx.w Missing
    else
      match Unix.single_write_substring p.input.fd s at (n - at) with
      | sent -> go (at + sent)
      | exception Unix.Unix_error (e, _, _) when Fs.retry e ->
        Poll.write_ready poll ctx p.input.fd;
        go at
      | exception Unix.Unix_error (e, _, _) -> Fs.failed ctx "write to" "this process" e
  in
  go 0

let close_input poll procs ctx (a : t array) : t =
  let _, p = process_arg procs ctx "CloseInput" a.(0) in
  finish poll p.input;
  Missing

(* Waits for the end, closes the pipes and gives the exit code. *)
let wait_exit poll procs ctx (a : t array) : t =
  let id, p = process_arg procs ctx "WaitExit" a.(0) in
  let code = exit_code ctx poll p.pid 0.0005 in
  finish poll p.input;
  finish poll p.output;
  Hashtbl.remove procs id;
  Int code

let stop_process procs ctx (a : t array) : t =
  let _, p = process_arg procs ctx "Stop" a.(0) in
  (try Unix.kill p.pid Sys.sigterm with Unix.Unix_error _ -> ());
  Missing

let natives poll =
  let procs = Hashtbl.create 8 in
  [ "Run", Native.nat ~result:true ~params:[| "cmd"; "args"; "input"; "dir"; "timeout" |] "Run" 1 5 (run poll);
    "Start", Native.nat ~result:true ~params:[| "cmd"; "args"; "dir" |] "Start" 1 3 (start_process poll procs);
    "ReadOutput", Native.nat ~result:true "ReadOutput" 1 1 (read_output poll procs);
    "Exit", Native.nat "Exit" 1 1 quit;
    "WriteInput", Native.nat ~result:true "WriteInput" 2 2 (write_input poll procs);
    "CloseInput", Native.nat "CloseInput" 1 1 (close_input poll procs);
    "WaitExit", Native.nat "WaitExit" 1 1 (wait_exit poll procs);
    "Stop", Native.nat "Stop" 1 1 (stop_process procs) ]
