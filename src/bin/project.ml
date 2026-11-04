open Cesia

type command =
  | Run of string list
  | File of { path : string; allow : string list; limit : string option; watch : bool }
  | Group

type task = { name : string; needs : string list; needs_line : int; command : command }
type project = { title : string; native : string list; tasks : task list }

exception Wrong of string

let file_name = "cesia.toml"
let wrong text = raise (Wrong text)
let wrong_at line text = wrong (Messages.at_line line text)

let text_field subject (e : Toml.entry) =
  match e.value with
  | Text s -> s
  | _ -> wrong_at e.line (Messages.project_type subject e.key "a string")

let texts_field subject (e : Toml.entry) =
  match e.value with
  | Texts l -> l
  | _ -> wrong_at e.line (Messages.project_type subject e.key "an array of strings")

let flag_field subject (e : Toml.entry) =
  match e.value with
  | Flag b -> b
  | _ -> wrong_at e.line (Messages.project_type subject e.key "true or false")

let read_project (table : Toml.table) =
  List.fold_left
    (fun (title, native) (e : Toml.entry) ->
       match e.key with
       | "name" -> Some (text_field "Project" e), native
       | "native" -> title, texts_field "Project" e
       | key -> wrong_at e.line (Messages.project_field "Project" key))
    (None, []) table.entries

let read_task (table : Toml.table) name =
  let subject = "Task " ^ name in
  List.iter
    (fun (e : Toml.entry) ->
       match e.key with
       | "needs" | "run" | "allow" -> ignore (texts_field subject e)
       | "file" | "limit" -> ignore (text_field subject e)
       | "watch" -> ignore (flag_field subject e)
       | key -> wrong_at e.line (Messages.project_field subject key))
    table.entries;
  (* From here a task has at most six entries. *)
  let find key = List.find_opt (fun (e : Toml.entry) -> String.equal e.key key) table.entries in
  let texts key = Option.fold ~none:[] ~some:(texts_field subject) (find key) in
  let command =
    match find "run", find "file" with
    | Some _, Some _ -> wrong_at table.start (Messages.project_both name)
    | Some e, None ->
      if texts_field subject e = [] then wrong_at e.line (Messages.project_empty_run name);
      Run (texts_field subject e)
    | None, Some e ->
      File
        { path = text_field subject e;
          allow = texts "allow";
          limit = Option.map (text_field subject) (find "limit");
          watch = Option.fold ~none:false ~some:(flag_field subject) (find "watch") }
    | None, None -> Group
  in
  (match command with
   | File _ -> ()
   | Run _ | Group ->
     List.iter
       (fun key ->
          if Option.is_some (find key) then wrong_at table.start (Messages.project_without_file name key))
       [ "allow"; "limit"; "watch" ]);
  let needs_line = Option.fold ~none:table.start ~some:(fun (e : Toml.entry) -> e.line) (find "needs") in
  { name; needs = texts "needs"; needs_line; command }

let index tasks =
  let by_name = Hashtbl.create 64 in
  List.iter (fun task -> Hashtbl.replace by_name task.name task) tasks;
  by_name

let check_needs by_name tasks =
  List.iter
    (fun task ->
       List.iter
         (fun need ->
            if not (Hashtbl.mem by_name need) then
              wrong_at task.needs_line (Messages.project_missing task.name need))
         task.needs)
    tasks

(* [path] holds the tasks being visited, the latest first. A task seen again in it closes a cycle. *)
let check_cycles by_name tasks =
  let finished = Hashtbl.create 64 in
  let rec visit path task =
    match Hashtbl.find_opt finished task.name with
    | Some true -> ()
    | Some false ->
      let rec through names = function
        | name :: rest when not (String.equal name task.name) -> through (name :: names) rest
        | _ -> names
      in
      wrong (Messages.project_cycle task.name (through [] path))
    | None ->
      Hashtbl.replace finished task.name false;
      List.iter (fun need -> visit (task.name :: path) (Hashtbl.find by_name need)) task.needs;
      Hashtbl.replace finished task.name true
  in
  List.iter (visit []) tasks

let of_tables (tables : Toml.table list) =
  let project = ref (None, []) and tasks = ref [] in
  List.iter
    (fun (table : Toml.table) ->
       match table.path, table.entries with
       | [], e :: _ -> wrong_at e.line (Messages.project_outside e.key)
       | [], [] -> ()
       | [ "project" ], _ -> project := read_project table
       | [ "tasks"; name ], _ -> tasks := read_task table name :: !tasks
       | path, _ -> wrong_at table.start (Messages.project_table (String.concat "." path)))
    tables;
  let tasks = List.rev !tasks in
  match !project with
  | None, _ -> wrong Messages.project_no_name
  | Some title, native ->
    if tasks = [] then wrong Messages.project_no_task;
    let by_name = index tasks in
    check_needs by_name tasks;
    check_cycles by_name tasks;
    { title; native; tasks }

let stop code text =
  prerr_endline text;
  exit code

let load () =
  if not (Sys.file_exists file_name) then stop 2 Messages.project_no_file;
  let src =
    try In_channel.with_open_bin file_name In_channel.input_all
    with Sys_error _ -> stop 2 (Messages.cant_read file_name)
  in
  match Toml.parse src with
  | Error (line, reason) -> stop 1 (Messages.at_line line reason)
  | Ok tables ->
    (match of_tables tables with
     | project -> project
     | exception Wrong text -> stop 1 text)

(* A printed line is a security display: a word can't draw a false one. *)
let is_plain = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' | '.' | '/' | ':' | '=' | ',' | '@' | '%' | '+' -> true
  | _ -> false

let quote word = if word <> "" && String.for_all is_plain word then word else Printf.sprintf "%S" word
let show words = String.concat " " (List.map quote words)

(* The arguments of [cesia run] for a program. *)
let program_args project path allow limit watch =
  let grants = List.map (fun library -> "ffi=" ^ library) project.native @ allow in
  (if grants = [] then [] else [ "--allow"; String.concat "," grants ])
  @ (match limit with None -> [] | Some value -> [ "--limit"; value ])
  @ (if watch then [ "--watch" ] else [])
  @ [ path ]

let words project task =
  match task.command with
  | Run words -> words
  | File { path; allow; limit; watch } -> "cesia" :: "run" :: program_args project path allow limit watch
  | Group -> []

let list project =
  print_string (quote project.title ^ "\n");
  let width = List.fold_left (fun w task -> max w (String.length task.name)) 0 project.tasks in
  List.iter
    (fun task ->
       let needs = if task.needs = [] then [] else [ Messages.project_listed_needs task.needs ] in
       let what = (match words project task with [] -> [] | words -> [ show words ]) @ needs in
       print_string (Printf.sprintf "  %-*s  %s\n" width task.name (String.concat " " what)))
    project.tasks

let stopped = ref false
let child = ref None

(* Ctrl-C reaches the child through the terminal. A signal sent to this process alone has to be passed on. A handler,
   and not Signal_ignore, which a child would inherit: leaving a child alone would be worse than waiting for it. *)
let on_stop signal =
  stopped := true;
  if signal = Sys.sigterm then
    Option.iter (fun pid -> try Unix.kill pid signal with Unix.Unix_error _ -> ()) !child

let catch_stops () =
  Sys.set_signal Sys.sigint (Sys.Signal_handle on_stop);
  Sys.set_signal Sys.sigterm (Sys.Signal_handle on_stop)

let rec wait pid =
  match Unix.waitpid [] pid with
  | _, status -> status
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> wait pid

(* Writes the line, runs the program, gives its exit code. *)
let spawn program arguments line =
  prerr_endline ("> " ^ line);
  let argv = Array.of_list (program :: arguments) in
  match Unix.create_process program argv Unix.stdin Unix.stdout Unix.stderr with
  | exception Unix.Unix_error (e, _, _) -> stop 1 (Messages.project_cant_start (quote program) (Unix.error_message e))
  | pid ->
    child := Some pid;
    let status = wait pid in
    child := None;
    (match status with
     | Unix.WEXITED code -> code
     | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 1)

let execute project task =
  let code =
    match task.command with
    | Group | Run [] -> 0
    | Run (program :: arguments) -> spawn program arguments (show (program :: arguments))
    | File { path; allow; limit; watch } ->
      spawn Sys.executable_name ("run" :: program_args project path allow limit watch) (show (words project task))
  in
  if code <> 0 then exit code;
  (* What came after didn't run, so this isn't a success, even if the child ended with 0. *)
  if !stopped then exit 1

let perform project by_name name =
  let seen = Hashtbl.create 16 in
  let rec visit task =
    if not (Hashtbl.mem seen task.name) then begin
      Hashtbl.replace seen task.name ();
      List.iter (fun need -> visit (Hashtbl.find by_name need)) task.needs;
      execute project task
    end
  in
  visit (Hashtbl.find by_name name)

let run args =
  match args with
  | [] -> list (load ())
  | [ name ] ->
    let project = load () in
    let by_name = index project.tasks in
    if not (Hashtbl.mem by_name name) then stop 1 (Messages.project_no_such_task name);
    catch_stops ();
    perform project by_name name
  | _ -> stop 2 Messages.usage

let write path text = Out_channel.with_open_bin path (fun oc -> output_string oc text)

let create name =
  let allowed = function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true | _ -> false in
  if name = "" || not (String.for_all allowed name) then stop 2 (Messages.project_bad_name (quote name));
  if Sys.file_exists name then stop 1 (Messages.project_exists name);
  Sys.mkdir name 0o755;
  let code = Filename.concat name "src" in
  Sys.mkdir code 0o755;
  write (Filename.concat name file_name)
    (Printf.sprintf "[project]\nname = \"%s\"\n\n[tasks.run]\nfile = \"src/main.ce\"\n" name);
  write (Filename.concat code "main.ce") (Printf.sprintf "Print(\"Hello from %s\")\n" name);
  print_endline (Messages.project_created name)
