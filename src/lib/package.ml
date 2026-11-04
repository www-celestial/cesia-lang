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

let library upath =
  let n = String.length upath in
  if n > 4 && String.starts_with ~prefix:"pkg/" upath && not (String.contains_from upath 4 '/') then
    Some (String.sub upath 4 (n - 4))
  else None

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
