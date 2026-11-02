let project_file = "kepler.toml"
let suffix = ".k"
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

let folder root upath =
  let in_src = Filename.concat (Filename.concat root "src") upath in
  if is_dir in_src then in_src else Filename.concat root upath

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

let shown path =
  let here = Sys.getcwd () ^ "/" in
  if String.starts_with ~prefix:here path then
    String.sub path (String.length here) (String.length path - String.length here)
  else path
