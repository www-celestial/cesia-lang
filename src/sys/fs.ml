open Cesia
open Types

let failure = Value.failure
let io_error w text = failure w "io" text
let reason e = String.uncapitalize_ascii (Unix.error_message e)
let stat_keys = Trie.names [| "Size"; "Modified"; "IsDir"; "IsFile"; "IsLink" |]
let failed ctx verb target e = io_error ctx.w (Messages.io_failure verb target (reason e)).text

let retry = function
  | Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR -> true
  | _ -> false

(* Runs an operation on [path]: its value in an Ok, or a failure in an Err. *)
let attempt ctx verb path f =
  match f () with
  | v -> Value.ok ctx.w v
  | exception Unix.Unix_error (e, _, _) -> failed ctx verb path e

(* Where a path leads, for the checks of read= and write=: what exists, as realpath tells; what doesn't yet, the folder that
   will hold it, then its name; a link that leads nowhere, where it leads, since writing it creates that. A path that is
   there but can't be resolved fails to open too: its text stands. None past 40 links. Windows writes \, the checks /. *)
let real_path path =
  let slashes p = if Sys.win32 then String.map (function '\\' -> '/' | c -> c) p else p in
  let rec go links p =
    if links > 40 then None
    else
      match Unix.realpath p with
      | r -> Some (slashes r)
      | exception Unix.Unix_error _ ->
        match Unix.lstat p with
        | { st_kind = Unix.S_LNK; _ } ->
          let target = Unix.readlink p in
          go (links + 1) (if Filename.is_relative target then Filename.concat (Filename.dirname p) target else target)
        | _ -> Some (slashes (Package.absolute p))
        | exception Unix.Unix_error _ ->
          let parent = Filename.dirname p in
          if parent = p then Some (slashes p)
          else
            Option.map
              (fun d -> match Filename.basename p with "." -> d | ".." -> Filename.dirname d | name -> Filename.concat d name)
              (go links parent)
  in
  go 0 path

let path_arg ctx name perm v =
  let path = Native.text_arg ctx name v in
  Runtime.check_perm ctx perm (Some path);
  path

let with_fd path flags f =
  let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) 0o644 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

let read_all ctx path =
  with_fd path [ Unix.O_RDONLY ] (fun fd ->
      let size = (Unix.fstat fd).Unix.st_size in
      Runtime.build ctx ((size / 8) + 1);
      let b = Buffer.create (size + 1) and chunk = Bytes.create 65536 in
      let rec go () =
        match Unix.read fd chunk 0 65536 with
        | 0 -> Text (Buffer.contents b)
        | n ->
          Runtime.reserve ctx ((n / 8) + 1);
          Buffer.add_subbytes b chunk 0 n;
          go ()
      in
      go ())

let write_all path flags text =
  with_fd path (Unix.O_WRONLY :: Unix.O_CREAT :: flags) (fun fd ->
      let n = String.length text in
      let rec go at = if at < n then go (at + Unix.write_substring fd text at (n - at)) in
      go 0;
      Missing)

let list_dir path =
  let d = Unix.opendir path in
  Fun.protect ~finally:(fun () -> Unix.closedir d) (fun () ->
      let rec go acc =
        match Unix.readdir d with
        | "." | ".." -> go acc
        | name -> go (name :: acc)
        | exception End_of_file -> acc
      in
      let names = Array.of_list (List.sort compare (go [])) in
      Array { rows = 1; cols = Array.length names; store = V (Array.map (fun n -> Text n) names); a_owned = true; a_tip = true })

(* Depth first, the names of each folder sorted: what isn't a folder is listed, a link too, never followed, so that no walk
   loops. The paths start with the folder, but for ".": a.txt, not ./a.txt. *)
let paths ?(skip = fun _ _ -> false) path =
  let rec go dir acc =
    let d = Unix.opendir dir in
    (* A failed close says nothing more: an exception of Fun.protect would escape as no Cesia error. *)
    let names =
      Fun.protect ~finally:(fun () -> try Unix.closedir d with Unix.Unix_error _ -> ()) (fun () ->
          let rec read acc =
            match Unix.readdir d with "." | ".." -> read acc | n -> read (n :: acc) | exception End_of_file -> acc
          in
          List.sort compare (read []))
    in
    List.fold_left
      (fun acc name ->
         let p = if dir = "." then name else if String.ends_with ~suffix:"/" dir then dir ^ name else dir ^ "/" ^ name in
         if skip dir name then acc else if (Unix.lstat p).st_kind = Unix.S_DIR then go p acc else p :: acc)
      acc names
  in
  List.rev (go (if path = "./" then "." else path) [])

let walk path =
  let paths = Array.of_list (List.map (fun p -> Text p) (paths path)) in
  Array { rows = 1; cols = Array.length paths; store = V paths; a_owned = true; a_tip = true }

(* A folder and all it holds; a link goes, never what it points to. Errors are ignored: what stays, stays. *)
let rec remove_tree path =
  match (Unix.lstat path).st_kind with
  | Unix.S_DIR ->
    (try Array.iter (fun n -> remove_tree (Filename.concat path n)) (Sys.readdir path) with Sys_error _ -> ());
    (try Unix.rmdir path with Unix.Unix_error _ -> ())
  | _ -> (try Unix.unlink path with Unix.Unix_error _ -> ())
  | exception Unix.Unix_error _ -> ()

(* A link goes, never what it points to. *)
let remove path =
  (if (Unix.lstat path).st_kind = Unix.S_DIR then Unix.rmdir else Unix.unlink) path;
  Missing

(* With parents, like mkdir -p: a folder that exists is fine. *)
let rec make_dir path =
  let parent = Filename.dirname path in
  if parent <> path && not (Sys.file_exists parent) then make_dir parent;
  try Unix.mkdir path 0o755
  with Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory path -> ()

let on_path name perm verb arity f =
  name,
  Native.nat ~result:true name arity arity (fun ctx a ->
      let path = path_arg ctx name perm a.(0) in
      attempt ctx verb path (fun () -> f ctx path a))

let natives =
  [ on_path "Read" Read "read" 1 (fun ctx path _ -> read_all ctx path);
    on_path "Write" Write "write" 2 (fun ctx path a ->
        write_all path [ Unix.O_TRUNC ] (Native.text_arg ctx "Write" a.(1)));
    on_path "Append" Write "append to" 2 (fun ctx path a ->
        write_all path [ Unix.O_APPEND ] (Native.text_arg ctx "Append" a.(1)));
    on_path "List" Read "list" 1 (fun _ path _ -> list_dir path);

    on_path "Remove" Write "remove" 1 (fun _ path _ -> remove path);
    on_path "Stat" Read "read" 1 (fun _ path _ ->
        let s = Unix.stat path in
        Trie.record stat_keys
          [| Int s.st_size; Float s.st_mtime; Value.of_bool (s.st_kind = Unix.S_DIR);
             Value.of_bool (s.st_kind = Unix.S_REG); Value.of_bool ((Unix.lstat path).st_kind = Unix.S_LNK) |]);
    on_path "Rename" Write "rename" 2 (fun ctx path a ->
        Unix.rename path (path_arg ctx "Rename" Write a.(1));
        Missing);
    on_path "Mkdir" Write "create" 1 (fun _ path _ -> make_dir path; Missing);
    (* A folder deep inside that fails is the one named. *)
    "Walk",
    Native.nat "Walk" 1 1 (fun ctx a ->
        let path = path_arg ctx "Walk" Read a.(0) in
        match walk path with
        | v -> Value.ok ctx.w v
        | exception Unix.Unix_error (e, _, at) -> failed ctx "list" (if at = "" then path else at) e);
    "Exists",
    Native.nat "Exists" 1 1 (fun ctx a -> Value.of_bool (Sys.file_exists (path_arg ctx "Exists" Read a.(0))));
    "Env",
    Native.nat "Env" 1 1 (fun ctx a ->
        let name = Native.text_arg ctx "Env" a.(0) in
        Runtime.check_perm ctx Env (Some name);
        match Sys.getenv_opt name with
        | Some v -> Text v
        | None -> Missing) ]
