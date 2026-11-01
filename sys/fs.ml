open Kepler
open Types

let failure = Value.failure
let io_error w text = failure w "io" text
let reason e = String.uncapitalize_ascii (Unix.error_message e)
let failed ctx verb target e = io_error ctx.w (Messages.io_failure verb target (reason e)).text

let retry = function
  | Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.EINTR -> true
  | _ -> false

(* Runs an operation on [path]: its value in an Ok, or a failure in an Err. *)
let attempt ctx verb path f =
  match f () with
  | v -> Value.ok ctx.w v
  | exception Unix.Unix_error (e, _, _) -> failed ctx verb path e

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
      Array { rows = 1; cols = Array.length names; store = V (Array.map (fun n -> Text n) names); a_owned = true })

let remove path =
  (if Sys.file_exists path && Sys.is_directory path then Unix.rmdir else Unix.unlink) path;
  Missing

(* With parents, like mkdir -p: a folder that exists is fine. *)
let rec make_dir path =
  let parent = Filename.dirname path in
  if parent <> path && not (Sys.file_exists parent) then make_dir parent;
  try Unix.mkdir path 0o755
  with Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory path -> ()

let on_path name perm verb arity f =
  name,
  Native.nat name arity arity (fun ctx a ->
      let path = path_arg ctx name perm a.(0) in
      attempt ctx verb path (fun () -> f ctx path a))

let natives =
  [ on_path "read" Read "read" 1 (fun ctx path _ -> read_all ctx path);
    on_path "write" Write "write" 2 (fun ctx path a ->
        write_all path [ Unix.O_TRUNC ] (Native.text_arg ctx "write" a.(1)));
    on_path "append" Write "append to" 2 (fun ctx path a ->
        write_all path [ Unix.O_APPEND ] (Native.text_arg ctx "append" a.(1)));
    on_path "list" Read "list" 1 (fun _ path _ -> list_dir path);
    on_path "remove" Write "remove" 1 (fun _ path _ -> remove path);
    on_path "stat" Read "read" 1 (fun ctx path _ ->
        let s = Unix.stat path in
        let shape = Value.shape_of ctx.w [| "size"; "modified"; "is_dir" |] in
        Struct
          { shape;
            fields = [| Int s.st_size; Float s.st_mtime; Value.of_bool (s.st_kind = Unix.S_DIR) |];
            r_owned = true });
    on_path "rename" Write "rename" 2 (fun ctx path a ->
        Unix.rename path (path_arg ctx "rename" Write a.(1));
        Missing);
    on_path "mkdir" Write "create" 1 (fun _ path _ -> make_dir path; Missing);
    "exists",
    Native.nat "exists" 1 1 (fun ctx a -> Value.of_bool (Sys.file_exists (path_arg ctx "exists" Read a.(0))));
    "env",
    Native.nat "env" 1 1 (fun ctx a ->
        let name = Native.text_arg ctx "env" a.(0) in
        Runtime.check_perm ctx Env (Some name);
        match Sys.getenv_opt name with
        | Some v -> Text v
        | None -> Missing) ]
