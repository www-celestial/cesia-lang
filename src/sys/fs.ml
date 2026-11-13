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

let with_fd ?(perm = 0o644) path flags f =
  let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) perm in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> f fd)

(* One string of the file's size, read in place: no copy at the end. A file that grows while it is read is read on to
   its end, past that size, through a Buffer; one that shrinks gives what it had. *)
let read_all ctx path =
  with_fd path [ Unix.O_RDONLY ] (fun fd ->
      let size = (Unix.fstat fd).Unix.st_size in
      Runtime.build ctx ((size / 8) + 1);
      let b = Bytes.create size in
      let rec fill at = if at = size then at else match Unix.read fd b at (size - at) with 0 -> at | n -> fill (at + n) in
      let got = fill 0 and chunk = Bytes.create 65536 in
      match if got < size then 0 else Unix.read fd chunk 0 65536 with
      | 0 -> Text (if got = size then Bytes.unsafe_to_string b else Bytes.sub_string b 0 got)
      | n ->
        let more = Buffer.create (size + n + 65536) in
        let rec go n =
          if n = 0 then Text (Buffer.contents more)
          else begin
            Runtime.reserve ctx ((n / 8) + 1);
            Buffer.add_subbytes more chunk 0 n;
            go (Unix.read fd chunk 0 65536)
          end
        in
        Buffer.add_bytes more b;
        go n)

(* The person's alone, 0700 for a folder and 0600 for a file, set on what is open: a link put in its place since changes
   nothing. One of someone else's is refused. Windows has no such modes: there a file takes the rights of its folder. A
   folder made so keeps what was opened before: a descriptor of it can still list its names. *)
let own fd = if not Sys.win32 then Unix.fchmod fd (if (Unix.fstat fd).st_kind = Unix.S_DIR then 0o700 else 0o600)

let put fd text =
  let n = String.length text in
  let rec go at = if at < n then go (at + Unix.write_substring fd text at (n - at)) in
  go 0

let sync_dir path = if not Sys.win32 then with_fd (Filename.dirname path) [ Unix.O_RDONLY ] Unix.fsync

(* With [sync], the text is on the disk before the Ok: the file by fsync, and its folder, which holds its name. *)
let write_all ?(sync = false) path flags text =
  with_fd path (Unix.O_WRONLY :: Unix.O_CREAT :: flags) (fun fd ->
      put fd text;
      if sync then (Unix.fsync fd; sync_dir path);
      Missing)

let rand = lazy (Random.State.make_self_init ())

(* A private text goes into a new file of the person's alone, made beside the path under a random name that no one can
   have opened, then renamed over the path: a reader of the old file keeps the old text, and a link at the path is
   replaced, its target untouched. A file of someone else's there is refused, and left as it was. *)
let write_private ~sync path text =
  (match Unix.lstat path with
   | st when (not Sys.win32) && st.st_uid <> Unix.getuid () -> raise (Unix.Unix_error (Unix.EPERM, "write", path))
   | _ | (exception Unix.Unix_error (Unix.ENOENT, _, _)) -> ());
  let tmp = Printf.sprintf "%s/.%s.%08x.tmp" (Filename.dirname path) (Filename.basename path) (Random.State.bits (Lazy.force rand)) in
  let fd = Unix.openfile tmp [ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ] 0o600 in
  try
    Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> own fd; put fd text; if sync then Unix.fsync fd);
    Unix.rename tmp path;
    if sync then sync_dir path;
    Missing
  with e -> (try Unix.unlink tmp with Unix.Unix_error _ -> ()); raise e

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
      Array { rows = 1; cols = Array.length names; store = V (Array.map (fun n -> Text n) names); a_owned = true; a_tip = true; dims = [||] })

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
  Array { rows = 1; cols = Array.length paths; store = V paths; a_owned = true; a_tip = true; dims = [||] }

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

(* With parents, like mkdir -p: a folder that exists is fine. Private, the folders it makes are 0700, and the last one is
   made so if it was there. *)
let rec make_dir ?(perm = 0o755) path =
  let parent = Filename.dirname path in
  if parent <> path && not (Sys.file_exists parent) then make_dir ~perm parent;
  try Unix.mkdir path perm
  with Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory path -> ()

let on_path ?params ?least name perm verb arity f =
  name,
  Native.nat ?params ~result:true name (Option.value least ~default:arity) arity (fun ctx a ->
      let path = path_arg ctx name perm a.(0) in
      attempt ctx verb path (fun () -> f ctx path a))

let natives =
  [ on_path "Read" Read "read" 1 (fun ctx path _ -> read_all ctx path);
    on_path ~params:[| "path"; "text"; "sync"; "private" |] ~least:2 "Write" Write "write" 4 (fun ctx path a ->
        let sync = Native.flag_arg ctx "sync" a 2 and text = Native.text_arg ctx "Write" a.(1) in
        if Native.flag_arg ctx "private" a 3 then write_private ~sync path text else write_all ~sync path [ Unix.O_TRUNC ] text);
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
    on_path ~params:[| "path"; "private" |] ~least:1 "Mkdir" Write "create" 2 (fun ctx path a ->
        let alone = Native.flag_arg ctx "private" a 1 in
        make_dir ~perm:(if alone then 0o700 else 0o755) path;
        if alone && not Sys.win32 then with_fd path [ Unix.O_RDONLY ] own;
        Missing);
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
