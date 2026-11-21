open Cesia
open Types

let failure = Value.failure
let io_error w text = failure w "io" text
let reason e = String.uncapitalize_ascii (Unix.error_message e)
let stat_keys = Trie.names [| "Size"; "Modified"; "IsDir"; "IsFile"; "IsLink"; "Mode" |]
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
          (* A link that another process removes or changes in between is looked at again. *)
          (match Unix.readlink p with
           | target -> go (links + 1) (if Filename.is_relative target then Filename.concat (Filename.dirname p) target else target)
           | exception Unix.Unix_error _ -> go (links + 1) p)
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

(* [name]: the act is on the name itself, a link that it names not followed. *)
let path_arg ?name ctx fn perm v =
  let path = Native.text_arg ctx fn v in
  Runtime.check_perm ?name ctx perm (Some path);
  path

let using fd f = Fun.protect ~finally:(fun () -> Unix.close fd) f

let with_fd ?(perm = 0o644) path flags f =
  let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) perm in
  using fd (fun () -> f fd)

(* Linux names each open file /proc/self/fd/N, a link to where the system holds it. Under a folder of read= or write=,
   an act is checked there again once its file or its folder is open, then done through that name: a link that another
   process swaps into the path after the first check can't lead the act out of the folder. Elsewhere, and with no
   folder to keep, the act is on the path as written. *)
external fd_number : Unix.file_descr -> int = "%identity"

let fd_place fd = "/proc/self/fd/" ^ string_of_int (fd_number fd)

let proc =
  lazy
    (Sys.os_type = "Unix"
     &&
     match Unix.openfile "/" [ O_RDONLY; O_CLOEXEC ] 0 with
     | fd -> using fd (fun () -> try Unix.readlink (fd_place fd) = "/" with Unix.Unix_error _ -> false)
     | exception Unix.Unix_error _ -> false)

let guarded ctx perm = Runtime.bounded ctx.w perm && Lazy.force proc

(* An open file of a checked path, checked again where the system holds it: closed and denied when that is out. *)
let held ctx perm path fd =
  if guarded ctx perm then
    try Runtime.check_perm ~at:(Unix.readlink (fd_place fd)) ctx perm (Some path) with e -> Unix.close fd; raise e

let opened ctx perm path flags =
  let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) 0o644 in
  held ctx perm path fd;
  fd

(* An act on a checked path through its folder, opened and checked again: the act names /proc/self/fd/N/name, which no
   link swapped into the folder's path can move. [name]: the last name is the one acted on, as the check took it. A
   folder that can be searched but not read can't be opened: there the act is on the path. *)
let through ?name ctx perm path f =
  match if guarded ctx perm then Runtime.leads ?name path else None with
  | None -> f path
  | Some real ->
    let dir = Filename.dirname real in
    match Unix.openfile dir [ O_RDONLY; O_CLOEXEC ] 0 with
    | exception Unix.Unix_error ((Unix.EACCES | Unix.EPERM), _, _) -> f path
    | d ->
      using d (fun () ->
          let at = fd_place d and base = if dir = real then "" else "/" ^ Filename.basename real in
          let place = Unix.readlink at in
          Runtime.check_perm ~at:((if place = "/" && base <> "" then "" else place) ^ base) ctx perm (Some path);
          f (at ^ base))

(* A file opened to write, made if it isn't there. Under a folder of write=, one that is there is opened, then seen
   inside before it is emptied; one that isn't is made only new, in its checked folder, never through a link: nothing
   out of the folder is made or cut. *)
let open_write ?(mode = 0o644) ~trunc ctx path flags =
  if not (guarded ctx Write) then
    Unix.openfile path (Unix.O_WRONLY :: O_CREAT :: O_CLOEXEC :: (if trunc then O_TRUNC :: flags else flags)) mode
  else
    let rec go tries p =
      match Unix.openfile p (Unix.O_WRONLY :: O_CLOEXEC :: flags) 0 with
      | fd -> held ctx Write path fd; fd
      | exception Unix.Unix_error (Unix.ENOENT, _, _) when tries > 0 ->
        through ctx Write path (fun p ->
            match Unix.openfile p (Unix.O_WRONLY :: O_CREAT :: O_EXCL :: O_CLOEXEC :: flags) mode with
            | fd -> fd
            | exception Unix.Unix_error (Unix.EEXIST, _, _) -> go (tries - 1) p)
    in
    let fd = go 3 path in
    (* What is no file, a pipe or a device, has nothing to cut. *)
    (if trunc then try Unix.ftruncate fd 0 with Unix.Unix_error (Unix.EINVAL, _, _) -> () | e -> Unix.close fd; raise e);
    fd

(* An act on a file of a checked path that the system can do by any name of it: under a folder, on the file opened and
   checked again, by its name in /proc. One that can't be opened is reached through its folder. *)
let on_open ctx perm path f =
  if not (guarded ctx perm) then f path
  else
    match opened ctx perm path [ Unix.O_RDONLY; O_NONBLOCK ] with
    | fd -> using fd (fun () -> f (fd_place fd))
    | exception Unix.Unix_error ((Unix.EACCES | Unix.EPERM), _, _) -> through ctx perm path f

(* One string of the file's size, read in place: no copy at the end. A file that grows while it is read is read on to
   its end, past that size, through a Buffer; one that shrinks gives what it had. *)
let read_all ctx path =
  let fd = opened ctx Read path [ Unix.O_RDONLY ] in
  using fd (fun () ->
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
let write_all ?(sync = false) ~trunc ctx path flags text =
  let fd = open_write ~trunc ctx path flags in
  using fd (fun () ->
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

let list_dir ctx path =
  on_open ctx Read path @@ fun path ->
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

external open_dir : int -> string -> int = "cesia_open_dir"
external unlink_at : int -> string -> bool -> unit = "cesia_unlink_at"
external names_at : int -> string list = "cesia_names"
external fd_of : int -> Unix.file_descr = "%identity"

(* A folder of the walk: its descriptor, -1 once closed; what it is, to know it again; its name in the one above; the
   names it holds that are left. *)
type level = { mutable fd : int; id : int * int; name : string; mutable left : string list }

(* On Linux and macOS, by descriptors, never by paths made again: each folder is opened from the one above it, never
   through a link (O_NOFOLLOW | O_DIRECTORY), its names read once, each removed from it. A link, or a file, swapped in
   is removed itself; a folder swapped for one is never entered. It walks with a list, not by recursion, and keeps the
   last 32 folders open: one above them is opened again from below by .., and must be the folder it left. [shown] names
   what failed. *)
let remove_walk path shown =
  let id fd = let st = Unix.fstat (fd_of fd) in st.st_dev, st.st_ino in
  let stack = ref [] in
  let close l = if l.fd >= 0 then (Unix.close (fd_of l.fd); l.fd <- -1) in
  let step extra f =
    try f ()
    with Unix.Unix_error (e, _, _) ->
      let below = List.rev (List.filter_map (fun l -> if l.name = "" then None else Some l.name) !stack) in
      List.iter close !stack;
      raise (Unix.Unix_error (e, "remove", String.concat "/" ((shown :: below) @ extra)))
  in
  match step [] (fun () -> open_dir (-1) path) with
  | exception Unix.Unix_error ((Unix.ENOTDIR | Unix.ELOOP | Unix.EMLINK), _, _) -> step [] (fun () -> unlink_at (-1) path false)
  | top ->
    let first = { fd = top; id = id top; name = ""; left = [] } in
    stack := [ first ];
    first.left <- step [] (fun () -> names_at top);
    while !stack <> [] do
      match !stack with
      | [] -> ()
      | l :: rest ->
        match l.left, rest with
        | name :: more, _ ->
          l.left <- more;
          (match open_dir l.fd name with
           | exception Unix.Unix_error ((Unix.ENOTDIR | Unix.ELOOP | Unix.EMLINK), _, _) -> step [ name ] (fun () -> unlink_at l.fd name false)
           | exception Unix.Unix_error (e, _, _) -> step [ name ] (fun () -> raise (Unix.Unix_error (e, "", "")))
           | fd ->
             let child = { fd; id = id fd; name; left = [] } in
             stack := child :: !stack;
             Option.iter close (List.nth_opt !stack 32);
             child.left <- step [] (fun () -> names_at fd))
        | [], [] -> close l; stack := []; step [] (fun () -> unlink_at (-1) path true)
        | [], up :: _ ->
          step [] (fun () ->
              if up.fd < 0 then begin
                let fd = open_dir l.fd ".." in
                up.fd <- fd;
                if id fd <> up.id then raise (Unix.Unix_error (Unix.EAGAIN, "", ""))
              end;
              unlink_at up.fd l.name true);
          close l;
          stack := rest
    done

(* Windows has no openat in OCaml: there the walk goes by paths, and enters a folder only if it is where its path leads,
   so that a junction or a link to a folder, a reparse point that lstat may take for a folder, goes alone and is never
   entered. A folder swapped for one between that check and the next step can still lead it out. *)
let rec remove_paths path =
  let real p = String.lowercase_ascii (Unix.realpath p) in
  match (Unix.lstat path).st_kind with
  | Unix.S_DIR when real path = String.lowercase_ascii (Filename.concat (real (Filename.dirname path)) (Filename.basename path)) ->
    Array.iter (fun n -> remove_paths (Filename.concat path n)) (Sys.readdir path);
    Unix.rmdir path
  | Unix.S_DIR -> Unix.rmdir path
  | _ -> Unix.unlink path

(* A folder and all it holds, as rm -r, a link never followed: one inside goes itself, and a path that is one goes alone.
   The first failure raises Unix_error, with the path of what failed. *)
let tree ?shown path = if Sys.win32 then remove_paths path else remove_walk path (Option.value shown ~default:path)

let remove_tree path = tree path

(* A link goes, never what it points to. *)
let remove path =
  (if (Unix.lstat path).st_kind = Unix.S_DIR then Unix.rmdir else Unix.unlink) path;
  Missing

(* The bytes of a file into another, chunk by chunk, with its mode and its times, as cp -p does: the copy is made or
   emptied first, so a folder, or the same file under another name, is refused before a byte is lost. *)
let copy_file ctx from dest =
  let src = opened ctx Read from [ Unix.O_RDONLY ] in
  using src (fun () ->
      let st = Unix.fstat src in
      if st.st_kind = Unix.S_DIR then raise (Unix.Unix_error (Unix.EISDIR, "copy", from));
      (match Unix.stat dest with
       | d when d.st_dev = st.st_dev && d.st_ino = st.st_ino -> raise (Unix.Unix_error (Unix.EINVAL, "copy", dest))
       | _ | (exception Unix.Unix_error (Unix.ENOENT, _, _)) -> ());
      let dst = open_write ~mode:st.st_perm ~trunc:true ctx dest [] in
      using dst (fun () ->
          let b = Bytes.create 65536 in
          let rec go () =
            match Unix.read src b 0 65536 with
            | 0 -> ()
            | n ->
              let rec put at = if at < n then put (at + Unix.write dst b at (n - at)) in
              put 0;
              go ()
          in
          go ();
          if not Sys.win32 then Unix.fchmod dst st.st_perm;
          (* For utimes, two times of 0.0 are now: the start of 1970 is read a millionth of a second after it. *)
          let atime = if st.st_atime = 0.0 && st.st_mtime = 0.0 then 1e-6 else st.st_atime in
          Unix.utimes (if Lazy.force proc then fd_place dst else dest) atime st.st_mtime));
  Missing

(* A mode of the permission bits, from 0 to 0o7777: setuid, setgid and sticky above the nine of read, write and run. *)
let mode_arg ctx name v =
  match v with
  | Int n when n >= 0 && n <= 0o7777 -> n
  | v -> Runtime.fail ctx Type (Messages.need_mode name (Value.describe v))

(* With parents, like mkdir -p: a folder that exists is fine. Private, the folders it makes are 0700, and the last one is
   made so if it was there. *)
let rec make_dir ?(perm = 0o755) path =
  let parent = Filename.dirname path in
  if parent <> path && not (Sys.file_exists parent) then make_dir ~perm parent;
  try Unix.mkdir path perm
  with Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory path -> ()

let on_path ?params ?least ?name:link fn perm verb arity f =
  fn,
  Native.nat ?params ~result:true fn (Option.value least ~default:arity) arity (fun ctx a ->
      let path = path_arg ?name:link ctx fn perm a.(0) in
      attempt ctx verb path (fun () -> f ctx path a))

let natives =
  [ on_path "Read" Read "read" 1 (fun ctx path _ -> read_all ctx path);
    on_path ~params:[| "path"; "text"; "sync"; "private" |] ~least:2 "Write" Write "write" 4 (fun ctx path a ->
        let sync = Native.flag_arg ctx "sync" a 2 and text = Native.text_arg ctx "Write" a.(1) in
        if Native.flag_arg ctx "private" a 3 then through ~name:true ctx Write path (fun p -> write_private ~sync p text)
        else write_all ~sync ~trunc:true ctx path [] text);
    on_path "Append" Write "append to" 2 (fun ctx path a ->
        write_all ~trunc:false ctx path [ Unix.O_APPEND ] (Native.text_arg ctx "Append" a.(1)));
    on_path "List" Read "list" 1 (fun ctx path _ -> list_dir ctx path);

    on_path ~name:true "Remove" Write "remove" 1 (fun ctx path _ -> through ~name:true ctx Write path remove);
    (* What failed deep inside is the path named. *)
    "RemoveTree",
    Native.nat ~result:true "RemoveTree" 1 1 (fun ctx a ->
        let path = path_arg ~name:true ctx "RemoveTree" Write a.(0) in
        match through ~name:true ctx Write path (tree ~shown:path) with
        | () -> Value.ok ctx.w Missing
        | exception Unix.Unix_error (e, _, at) -> failed ctx "remove" (if at = "" then path else at) e);
    on_path "Stat" Read "read" 1 (fun _ path _ ->
        let s = Unix.stat path in
        Trie.record stat_keys
          [| Int s.st_size; Float s.st_mtime; Value.of_bool (s.st_kind = Unix.S_DIR);
             Value.of_bool (s.st_kind = Unix.S_REG); Value.of_bool ((Unix.lstat path).st_kind = Unix.S_LNK); Int s.st_perm |]);
    on_path "Copy" Read "copy" 2 (fun ctx path a -> copy_file ctx path (path_arg ctx "Copy" Write a.(1)));
    on_path "Chmod" Write "change the mode of" 2 (fun ctx path a ->
        let mode = mode_arg ctx "Chmod" a.(1) in
        on_open ctx Write path (fun p -> Unix.chmod p mode);
        Missing);
    on_path "SetModified" Write "change the time of" 2 (fun ctx path a ->
        let t = match a.(1) with Int n -> float_of_int n | Float f -> f | v -> Runtime.fail ctx Type (Messages.need_number "SetModified" (Value.describe v)) in
        (* For utimes, 0.0 is now: the start of 1970 is asked a millionth of a second after it. *)
        let t = if t = 0.0 then 1e-6 else t in
        on_open ctx Write path (fun p -> Unix.utimes p t t);
        Missing);
    (* The link is the path that is written: what it points to is a text, read by no one here, and may not exist. *)
    "Symlink",
    Native.nat ~result:true "Symlink" 2 2 (fun ctx a ->
        let target = Native.text_arg ctx "Symlink" a.(0) and link = path_arg ~name:true ctx "Symlink" Write a.(1) in
        attempt ctx "create the link" link (fun () -> through ~name:true ctx Write link (Unix.symlink target); Missing));
    (* A hard link is the same file under a second name: every write through it writes the target. So the target must
       be granted to write, as well as to read. *)
    "Link",
    Native.nat ~result:true "Link" 2 2 (fun ctx a ->
        let target = path_arg ctx "Link" Read a.(0) in
        Runtime.check_perm ctx Write (Some target);
        let link = path_arg ~name:true ctx "Link" Write a.(1) in
        attempt ctx "create the link" link (fun () ->
            through ctx Write target (fun t -> through ~name:true ctx Write link (Unix.link t));
            Missing));
    on_path ~name:true "ReadLink" Read "read the link" 1 (fun ctx path _ ->
        through ~name:true ctx Read path (fun p -> Text (Unix.readlink p)));
    on_path ~name:true "Rename" Write "rename" 2 (fun ctx path a ->
        let dest = path_arg ~name:true ctx "Rename" Write a.(1) in
        through ~name:true ctx Write path (fun p -> through ~name:true ctx Write dest (Unix.rename p));
        Missing);
    on_path ~params:[| "path"; "private" |] ~least:1 "Mkdir" Write "create" 2 (fun ctx path a ->
        let alone = Native.flag_arg ctx "private" a 1 in
        let perm = if alone then 0o700 else 0o755 in
        let parent = Filename.dirname path in
        if parent <> path && not (Sys.file_exists parent) then make_dir ~perm parent;
        through ~name:true ctx Write path (make_dir ~perm);
        if alone && not Sys.win32 then (let fd = opened ctx Write path [ Unix.O_RDONLY ] in using fd (fun () -> own fd));
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
