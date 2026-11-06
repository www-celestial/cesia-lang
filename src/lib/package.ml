let project_file = "cesia.toml"
let suffix = ".ce"
let is_source path = Filename.check_suffix path suffix
let is_test path = Filename.check_suffix path (".test" ^ suffix)

let is_dir path = Sys.file_exists path && Sys.is_directory path

(* A test, a dot file as an editor leaves, or a folder named like a file isn't code of the package. *)
let is_code dir name =
  let path = Filename.concat dir name in
  name.[0] <> '.'
  && is_source name
  && (not (is_test name))
  && Sys.file_exists path
  && not (Sys.is_directory path)

let files dir =
  if is_dir dir then begin
    let names = Sys.readdir dir in
    Array.sort String.compare names;
    List.filter_map (fun n -> if is_code dir n then Some (Filename.concat dir n) else None) (Array.to_list names)
  end
  else []

let shown path =
  let here = Sys.getcwd () ^ "/" in
  if String.starts_with ~prefix:here path then
    String.sub path (String.length here) (String.length path - String.length here)
  else path

let wrong_cesia (tables : Toml.table list) =
  let check (e : Toml.entry) =
    match e.key, e.value with
    | "cesia", Text v when Version.valid v ->
      if Version.at_least v then None else Some (e.line, Messages.cesia_needed v Version.number)
    | "cesia", _ -> Some (e.line, Messages.plain (Messages.project_type "Project" "cesia" Messages.cesia_not_version))
    | _ -> None
  in
  List.find_map (fun (t : Toml.table) -> if t.path = [ "project" ] then List.find_map check t.entries else None) tables

(* The source folders of a root, from [project] src of its cesia.toml, read once: every use asks. *)
let known_sources = Hashtbl.create 4

let read_sources root =
  let file = Filename.concat root project_file in
  let wrong line (m : Messages.t) =
    raise (Pos.Load_error { file = shown file; pos = Pos.make line 1; kind = "name"; text = m.text; hint = m.hint })
  in
  let src = if Sys.file_exists file then In_channel.with_open_bin file In_channel.input_all else "" in
  match Toml.parse src with
  | Error (line, reason) -> wrong line (Messages.plain reason)
  | Ok tables ->
    Option.iter (fun (line, m) -> wrong line m) (wrong_cesia tables);
    let project = List.concat_map (fun (t : Toml.table) -> if t.path = [ "project" ] then t.entries else []) tables in
    match List.find_opt (fun (e : Toml.entry) -> String.equal e.key "src") project with
    | None -> [ "src" ]
    | Some { value = Texts dirs; line; _ } ->
      List.iter
        (fun dir ->
           let path = Runtime.normalize (Filename.concat root dir) in
           if not (Runtime.inside root path) then wrong line (Messages.source_outside dir);
           if not (is_dir path) then wrong line (Messages.source_missing dir))
        dirs;
      dirs
    | Some { line; _ } -> wrong line (Messages.plain (Messages.project_type "Project" "src" "an array of strings"))

let sources root =
  match Hashtbl.find_opt known_sources root with
  | Some dirs -> dirs
  | None ->
    let dirs = read_sources root in
    Hashtbl.replace known_sources root dirs;
    dirs

(* deps/OWNER/REPO, or deps/HOST/OWNER/REPO when the first part holds a dot: how many parts name the project. *)
let dep_depth = function
  | "deps" :: first :: _ when String.contains first '.' -> 4
  | "deps" :: _ -> 3
  | _ -> 0

let dep upath =
  let parts = String.split_on_char '/' upath in
  let depth = dep_depth parts in
  if depth = 0 || List.length parts <= depth || List.mem "" parts then None
  else
    let project = List.filteri (fun i _ -> i < depth) parts and package = List.filteri (fun i _ -> i >= depth) parts in
    Some (String.concat "/" project, String.concat "/" package)

let folder root upath =
  let rec first = function
    | [] -> Filename.concat root upath
    | dir :: rest ->
      let path = Filename.concat (Filename.concat root dir) upath in
      if is_dir path then path else first rest
  in
  first (sources root)

let absolute path = Runtime.normalize (if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path)

let root_of path =
  let start = absolute (if is_dir path then path else Filename.dirname path) in
  let rec up dir =
    if Sys.file_exists (Filename.concat dir project_file) then dir
    else
      let parent = Filename.dirname dir in
      if String.equal parent dir then start else up parent
  in
  up start

let lock_file = "cesia.lock"

(* The files of every table of a root's cesia.lock, read once: "std/rope/rope.ce blake2:...", the path from the root. A lock
   that doesn't read holds nothing, so that each file says it isn't installed. *)
let known_locks = Hashtbl.create 4

let read_lock root =
  let table = Hashtbl.create 64 in
  let file = Filename.concat root lock_file in
  let src = if Sys.file_exists file then In_channel.with_open_bin file In_channel.input_all else "" in
  (match Toml.parse src with
   | Error _ -> ()
   | Ok tables ->
     List.iter
       (fun (t : Toml.table) ->
          List.iter
            (fun (e : Toml.entry) ->
               match e.key, e.value with
               | "files", Texts lines ->
                 List.iter
                   (fun line ->
                      match String.rindex_opt line ' ' with
                      | Some i ->
                        let path = Runtime.normalize (Filename.concat root (String.sub line 0 i)) in
                        Hashtbl.replace table path (String.sub line (i + 1) (String.length line - i - 1))
                      | None -> ())
                   lines
               | _ -> ())
            t.entries)
       tables);
  table

let lock root =
  match Hashtbl.find_opt known_locks root with
  | Some table -> table
  | None ->
    let table = read_lock root in
    Hashtbl.replace known_locks root table;
    table

let installed root path =
  let path = absolute path in
  let from = root ^ "/" in
  if not (String.starts_with ~prefix:from path) then None
  else
    let parts = String.split_on_char '/' (String.sub path (String.length from) (String.length path - String.length from)) in
    let depth = match parts with "std" :: _ -> 2 | _ -> dep_depth parts in
    if depth = 0 || List.length parts <= depth then None else Some (String.concat "/" (List.filteri (fun i _ -> i < depth) parts))
