open Cesia
open Types

let failure = Value.failure
let io_error w text = failure w "io" text
let reason e = String.uncapitalize_ascii (Unix.error_message e)
let stat_keys = Trie.names [| "Size"; "Modified"; "IsDir"; "IsFile"; "IsLink"; "Mode"; "Owner"; "Group" |]
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

let using fd f = Fun.protect ~finally:(fun () -> Unix.close fd) f

let with_fd ?(perm = 0o644) path flags f =
  let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) perm in
  using fd (fun () -> f fd)

(* Linux names each open file /proc/self/fd/N, a link to where the system holds it. Under a folder of read= or write=,
   an act is done through the name of its open file or folder there: a link that another process swaps into the path
   after the check can't lead the act out of the folder. Where the system has openat2, the file or the folder is opened
   from the folder of the grant, which the kernel keeps the open below; elsewhere it is opened by its path, then checked
   again where the system holds it. Off Linux, and with no folder to keep, the act is on the path as written. *)
external fd_number : Unix.file_descr -> int = "%identity"
external fd_of : int -> Unix.file_descr = "%identity"

let fd_place fd = "/proc/self/fd/" ^ string_of_int (fd_number fd)

let proc =
  lazy
    (Sys.os_type = "Unix"
     &&
     match Unix.openfile "/" [ O_RDONLY; O_CLOEXEC ] 0 with
     | fd -> using fd (fun () -> try Unix.readlink (fd_place fd) = "/" with Unix.Unix_error _ -> false)
     | exception Unix.Unix_error _ -> false)

(* What OCaml's Unix lacks, on Linux and macOS (stubs.c): the open of a name from a folder open above it, -1 for the
   current one, with the flags below in [how]; with [o_beneath], by openat2, which refuses in the same call, with EXDEV,
   a walk that leaves the folder. Then a name of an open folder removed, made a folder, made a link or renamed, a link
   read, the names a folder holds, and the mode and the times of an open file given to another, as cp -p does. *)
external open_at : int -> string -> int -> int -> int = "cesia_open_at"
external unlink_at : int -> string -> bool -> unit = "cesia_unlink_at"
external mkdir_at : int -> string -> int -> unit = "cesia_mkdir_at"
external symlink_at : string -> int -> string -> unit = "cesia_symlink_at"
external rename_at : int -> string -> string -> unit = "cesia_rename_at"
external readlink_at : int -> string -> string = "cesia_readlink_at"
external names_at : int -> string list = "cesia_names"
external copy_meta : int -> int -> unit = "cesia_copy_meta"

let o_write = 1 and o_create = 2 and o_trunc = 4 and o_append = 8 and o_excl = 16 and o_nofollow = 32
let o_nonblock = 64 and o_dir = 128 and o_path = 256 and o_beneath = 512

let how_of =
  List.fold_left
    (fun h f ->
       h lor match f with
       | Unix.O_WRONLY -> o_write | O_CREAT -> o_create | O_TRUNC -> o_trunc | O_APPEND -> o_append | O_EXCL -> o_excl
       | O_NONBLOCK -> o_nonblock | _ -> 0)
    0

(* openat2 is in Linux 5.6 and later, unless a filter of system calls refuses it, as some containers do. *)
let beneath =
  lazy
    (Lazy.force proc
     &&
     match open_at (-1) "." (o_path lor o_dir lor o_beneath) 0 with
     | fd -> Unix.close (fd_of fd); true
     | exception Unix.Unix_error _ -> false)

let guarded ctx perm = Runtime.bounded ctx.w perm && Lazy.force proc
let fast ctx perm = guarded ctx perm && Lazy.force beneath

(* [name]: the act is on the name itself, a link that it names not followed. [below]: the act opens the path by
   [checked_below] where the system has openat2, which checks it there: a check before, by where it leads, would cost
   a system call for each of its folders. Only an act on one path waits so: one on two checks both first, in order, as
   before. *)
let path_arg ?name ?(below = false) ctx fn perm v =
  let path = Native.text_arg ctx fn v in
  if not (below && fast ctx perm) then Runtime.check_perm ?name ctx perm (Some path);
  path

(* Has a path the name .. in it? After a link, .. is not where its text says. *)
let dotdot p =
  let n = String.length p in
  let rec go i =
    i < n
    && (let j = Option.value (String.index_from_opt p i '/') ~default:n in
        (j = i + 2 && p.[i] = '.' && p.[i + 1] = '.') || go (j + 1))
  in
  go 0

(* What is left of a place below a folder, both normalized, absolute or both from the current folder, without ..: "."
   for the folder itself, None out of it. *)
let below dir place =
  if place = dir then Some "."
  else if dir = "." then Some place
  else
    let pre = if dir = "/" then dir else dir ^ "/" in
    let n = String.length pre in
    if String.starts_with ~prefix:pre place then Some (String.sub place n (String.length place - n)) else None

(* A folder of a grant of [perm] that holds where a path leads, as Runtime.granted finds one: as it is written, made
   absolute, or where it leads; with what is left of the place below it. *)
let holder ctx perm place =
  List.find_map
    (function
      | p, Some s when p = perm ->
        let at d = Option.map (fun r -> d, r) (below d place) in
        (match if dotdot s then None else at (Package.absolute s) with
         | None -> Option.bind (real_path s) (fun d -> at (Runtime.normalize d))
         | hit -> hit)
      | _ -> None)
    ctx.w.grants.perms

(* A folder of a grant of [perm] that holds a path as it is written, and the path below it: with no system call when
   both are written from the same place, the root or the current folder, which the open then starts from; else both
   made absolute. *)
let holder_written ctx perm path =
  let from_here = Filename.is_relative path in
  List.find_map
    (function
      | p, Some s when p = perm && not (dotdot s) ->
        let d, place =
          if Filename.is_relative s = from_here then Runtime.normalize s, Runtime.normalize path
          else Package.absolute s, Package.absolute path
        in
        Option.map (fun r -> d, r) (below d place)
      | _ -> None)
    ctx.w.grants.perms

(* [rel] opened below the folder [dir] by openat2, with the flags of [how]: the kernel refuses a walk out of it. The
   path of a grant itself, a folder or a file, "." below it, is opened where that path leads, as the grant holds. *)
let open_below (dir, rel) how mode =
  if rel = "." then fd_of (open_at (-1) dir how mode)
  else
    let d = fd_of (open_at (-1) dir (o_path lor o_dir) 0) in
    using d (fun () -> fd_of (open_at (fd_number d) rel (how lor o_beneath) mode))

(* An open under the folders of read= or write= by openat2, from the folder of the grant that holds the path, so that
   no link swapped into the path can lead it out: first as the path is written, with no system call; if it leads out
   on the way, as a link that comes back in may, where the path leads, once checked; out still, it is denied. A path
   with .., a last / or a last ., which the system reads its own way, is taken where it leads at once, as with [quick]
   false, for an act that follows the last name through the folder that holds it. [open_from] opens a place below a
   folder; with [name], the act is on the name itself. *)
let checked_below ?(name = false) ?(quick = true) ctx perm path open_from =
  let checked () =
    let place = Option.map Runtime.normalize (Runtime.leads ~name path) in
    Runtime.check_perm ~name ?at:place ctx perm (Some path);
    (* A last / asks for a folder, as the system reads it: the place keeps it. *)
    let slash (dir, rel) = if (not name) && String.ends_with ~suffix:"/" path then dir, rel ^ "/" else dir, rel in
    match Option.bind place (holder ctx perm) with
    | Some h -> (try open_from (slash h) with Unix.Unix_error (Unix.EXDEV, _, _) -> Runtime.deny ctx perm (Some path))
    | None -> Runtime.deny ctx perm (Some path)
  in
  let plain =
    quick && (match Filename.basename path with "." | ".." -> false | _ -> true)
    && not (dotdot path || String.ends_with ~suffix:"/" path)
  in
  match if plain then holder_written ctx perm path else None with
  | Some h -> (try open_from h with Unix.Unix_error ((Unix.EXDEV | Unix.ELOOP), _, _) -> checked ())
  | None -> checked ()

(* An open file of a checked path, checked again where the system holds it: closed and denied when that is out. *)
let held ctx perm path fd =
  if guarded ctx perm then
    try Runtime.check_perm ~at:(Unix.readlink (fd_place fd)) ctx perm (Some path) with e -> Unix.close fd; raise e

let opened ctx perm path flags =
  if fast ctx perm then checked_below ctx perm path (fun h -> open_below h (how_of flags) 0)
  else begin
    let fd = Unix.openfile path (Unix.O_CLOEXEC :: flags) 0o644 in
    held ctx perm path fd;
    fd
  end

(* An act on a checked path through its folder, opened, below the folder of its grant or checked again: the act names
   /proc/self/fd/N/name, which no link swapped into the folder's path can move. [name]: the last name is the one acted
   on, as the check took it; else the act follows it, and the path is taken where it leads. The folder of a grant itself
   is reached from the one above it. By the path, a folder that can be searched but not read can't be opened: there
   the act is on the path. *)
let through ?(name = false) ctx perm path f =
  if fast ctx perm then
    let d, base =
      checked_below ~name ~quick:name ctx perm path (fun (dir, rel) ->
          if rel = "." then fd_of (open_at (-1) (Filename.dirname dir) (o_path lor o_dir) 0), Filename.basename dir
          else open_below (dir, Filename.dirname rel) (o_path lor o_dir) 0, Filename.basename rel)
    in
    using d (fun () -> f (fd_place d ^ "/" ^ base))
  else
    match if guarded ctx perm then Runtime.leads ~name path else None with
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

(* What is no file, a pipe or a device, has nothing to cut. *)
let cut fd = try Unix.ftruncate fd 0 with Unix.Unix_error (Unix.EINVAL, _, _) -> ()

(* A file opened to write, made if it isn't there, with [mode]; with [fresh], made only new: one that is there is an
   Err, a link too, never followed, so that the act is on the name, checked as such; with [create] false, never made.
   Under a folder of write=, with openat2, below its folder; else one that is there is opened, then seen inside before
   it is emptied, and one that isn't is made only new, in its checked folder, never through a link: nothing out of the
   folder is made or cut. *)
let open_write ?(mode = 0o644) ?(fresh = false) ?(create = true) ~trunc ctx path flags =
  let how = o_write lor how_of flags lor (if create then o_create else 0) lor (if fresh then o_excl lor o_nofollow else 0) in
  let how = if trunc then how lor o_trunc else how in
  if fast ctx Write then checked_below ~name:fresh ctx Write path (fun h -> open_below h how mode)
  else if not (guarded ctx Write) then
    let flags = if fresh then Unix.O_EXCL :: flags else flags in
    let flags = if create then Unix.O_CREAT :: flags else flags in
    Unix.openfile path (Unix.O_WRONLY :: O_CLOEXEC :: (if trunc then O_TRUNC :: flags else flags)) mode
  else
    let make p = Unix.openfile p (Unix.O_WRONLY :: O_CREAT :: O_EXCL :: O_CLOEXEC :: flags) mode in
    let rec go tries p =
      match Unix.openfile p (Unix.O_WRONLY :: O_CLOEXEC :: flags) 0 with
      | fd -> held ctx Write path fd; fd
      | exception Unix.Unix_error (Unix.ENOENT, _, _) when tries > 0 && create ->
        through ctx Write path (fun p -> try make p with Unix.Unix_error (Unix.EEXIST, _, _) -> go (tries - 1) p)
    in
    let fd = if fresh then through ~name:true ctx Write path make else go 3 path in
    (if trunc then try cut fd with e -> Unix.close fd; raise e);
    fd

(* An act on a file of a checked path that the system can do by any name of it: under a folder, on the file opened and
   checked, by its name in /proc. With openat2, the file is opened as a place only, O_PATH, which needs no right to
   read it; else, one that can't be opened is reached through its folder. *)
let on_open ctx perm path f =
  if fast ctx perm then
    let fd = checked_below ctx perm path (fun h -> open_below h o_path 0) in
    using fd (fun () -> f (fd_place fd))
  else if not (guarded ctx perm) then f path
  else
    match opened ctx perm path [ Unix.O_RDONLY; O_NONBLOCK ] with
    | fd -> using fd (fun () -> f (fd_place fd))
    | exception Unix.Unix_error ((Unix.EACCES | Unix.EPERM), _, _) -> through ctx perm path f

(* One string of the file's size, read in place: no copy at the end, which is a read that gives nothing, of one byte.
   A file that the system says is empty, as those of /proc, is read into a page. One that grows while it is read, or
   fills that page, is read on to its end, past its size, through a Buffer; one that shrinks gives what it had. *)
let read_all ctx path =
  let fd = opened ctx Read path [ Unix.O_RDONLY ] in
  using fd (fun () ->
      let size = (Unix.fstat fd).Unix.st_size in
      Runtime.build ctx ((size / 8) + 1);
      let b = Bytes.create (if size = 0 then 4096 else size) in
      let n = Bytes.length b in
      let rec fill at = if at = n then at else match Unix.read fd b at (n - at) with 0 -> at | k -> fill (at + k) in
      let got = fill 0 and one = Bytes.create 1 in
      if got < n || Unix.read fd one 0 1 = 0 then Text (if got = n then Bytes.unsafe_to_string b else Bytes.sub_string b 0 got)
      else begin
        let more = Buffer.create (2 * n + 1) and chunk = Bytes.create 65536 in
        Buffer.add_bytes more b;
        Buffer.add_bytes more one;
        let rec go k =
          if k = 0 then Text (Buffer.contents more)
          else begin
            Runtime.reserve ctx ((k / 8) + 1);
            Buffer.add_subbytes more chunk 0 k;
            go (Unix.read fd chunk 0 65536)
          end
        in
        go (Unix.read fd chunk 0 65536)
      end)

(* The person's alone, 0700 for a folder and 0600 for a file, set on what is open: a link put in its place since changes
   nothing. One of someone else's is refused. Windows has no such modes: there a file takes the rights of its folder. A
   folder made so keeps what was opened before: a descriptor of it can still list its names. *)
let own fd = if not Sys.win32 then Unix.fchmod fd (if (Unix.fstat fd).st_kind = Unix.S_DIR then 0o700 else 0o600)

(* A group, then a mode, given to an open file before its text is in: a change of group takes setuid and setgid away.
   Windows has neither on a descriptor. *)
let give ?mode ?group fd =
  if not Sys.win32 then begin
    Option.iter (fun g -> Unix.fchown fd (-1) g) group;
    Option.iter (Unix.fchmod fd) mode
  end

(* setuid and setgid, which a write takes away, given again once the text is in. *)
let give_again ?mode fd = match mode with Some m when m land 0o6000 <> 0 && not Sys.win32 -> Unix.fchmod fd m | _ -> ()

let put fd text =
  let n = String.length text in
  let rec go at = if at < n then go (at + Unix.write_substring fd text at (n - at)) in
  go 0

let sync_dir path = if not Sys.win32 then with_fd (Filename.dirname path) [ Unix.O_RDONLY ] Unix.fsync

(* The umask of the program, which no act of Cesia changes: read once, by setting it to 0077 for that moment, so that a
   file made meanwhile by another domain is only more private. *)
let umask = lazy (if Sys.win32 then 0 else let u = Unix.umask 0o077 in ignore (Unix.umask u); u)

(* With [sync], the text is on the disk before the Ok: the file by fsync, and its folder, which holds its name. With
   [mode] or [group], the file takes them on its descriptor before its old text is cut, then the new one is in. A file
   made then is its owner's alone, 0600, until it has them, so that no one of the person's group can open it before
   its group is given, then read the text through it; given a group alone, it then takes the mode of a new file, 0644
   less the umask. On Windows the mode is given to the path once the text is in, and the group changes nothing. *)
let write_all ?(sync = false) ?mode ?group ~trunc ctx path flags text =
  let keep = mode <> None || group <> None in
  let fd, made =
    if not keep then open_write ~trunc ctx path flags, false
    else if mode <> None then open_write ~mode:0o600 ~trunc:false ctx path flags, false
    else
      match open_write ~create:false ~trunc:false ctx path flags with
      | fd -> fd, false
      | exception Unix.Unix_error (Unix.ENOENT, _, _) -> open_write ~mode:0o600 ~trunc:false ctx path flags, true
  in
  using fd (fun () ->
      if keep then begin
        give ?mode ?group fd;
        if made && not Sys.win32 then Unix.fchmod fd (0o644 land lnot (Lazy.force umask));
        if trunc then cut fd
      end;
      put fd text;
      give_again ?mode fd;
      if sync then (Unix.fsync fd; sync_dir path));
  if Sys.win32 then Option.iter (Unix.chmod path) mode;
  Missing

let rand = lazy (Random.State.make_self_init ())

(* A private text goes into a new file of the person's alone, made beside the path under a random name that no one can
   have opened, then renamed over the path: a reader of the old file keeps the old text, and a link at the path is
   replaced, its target untouched. A file of someone else's there is refused, and left as it was. *)
let write_private ~sync ?mode ?group path text =
  (match Unix.lstat path with
   | st when (not Sys.win32) && st.st_uid <> Unix.getuid () -> raise (Unix.Unix_error (Unix.EPERM, "write", path))
   | _ | (exception Unix.Unix_error (Unix.ENOENT, _, _)) -> ());
  let tmp = Printf.sprintf "%s/.%s.%08x.tmp" (Filename.dirname path) (Filename.basename path) (Random.State.bits (Lazy.force rand)) in
  let fd = Unix.openfile tmp [ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ] 0o600 in
  try
    Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
        own fd;
        give ?mode ?group fd;
        put fd text;
        give_again ?mode fd;
        if sync then Unix.fsync fd);
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

(* A folder opened from one open above it, -1 the current one, never through a link. *)
let open_dir dir name = open_at dir name (o_dir lor o_nofollow) 0

let ident fd = let st = Unix.fstat (fd_of fd) in st.st_dev, st.st_ino

(* A folder of the walk: its descriptor, -1 once closed; what it is, to know it again; its name in the one above; the
   names it holds that are left. *)
type level = { mutable fd : int; id : int * int; name : string; mutable left : string list }

(* On Linux and macOS, by descriptors, never by paths made again: each folder is opened from the one above it, never
   through a link (O_NOFOLLOW | O_DIRECTORY), its names read once, each removed from it. A link, or a file, swapped in
   is removed itself; a folder swapped for one is never entered. It walks with a list, not by recursion, and keeps the
   last 32 folders open: one above them is opened again from below by .., and must be the folder it left. [shown] names
   what failed. *)
let remove_walk path shown =
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
    let first = { fd = top; id = ident top; name = ""; left = [] } in
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
             let child = { fd; id = ident fd; name; left = [] } in
             stack := child :: !stack;
             Option.iter close (List.nth_opt !stack 32);
             child.left <- step [] (fun () -> names_at fd))
        | [], [] -> close l; stack := []; step [] (fun () -> unlink_at (-1) path true)
        | [], up :: _ ->
          step [] (fun () ->
              if up.fd < 0 then begin
                let fd = open_dir l.fd ".." in
                up.fd <- fd;
                if ident fd <> up.id then raise (Unix.Unix_error (Unix.EAGAIN, "", ""))
              end;
              unlink_at up.fd l.name true);
          close l;
          stack := rest
    done

(* Is this folder, by its path, where its path leads: no junction nor link to a folder, a reparse point that lstat on
   Windows may take for a folder? *)
let plain_dir path =
  let real p = String.lowercase_ascii (Unix.realpath p) in
  real path = String.lowercase_ascii (Filename.concat (real (Filename.dirname path)) (Filename.basename path))

(* Windows has no openat in OCaml: there the walk goes by paths, and enters a folder only if it is where its path leads,
   so that a junction or a link to a folder goes alone and is never entered. A folder swapped for one between that check
   and the next step can still lead it out. *)
let rec remove_paths path =
  match (Unix.lstat path).st_kind with
  | Unix.S_DIR when plain_dir path ->
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

(* The bytes of an open file into another, chunk by chunk. *)
let copy_bytes src dst =
  let b = Bytes.create 65536 in
  let rec go () =
    match Unix.read src b 0 65536 with
    | 0 -> ()
    | n ->
      let rec put at = if at < n then put (at + Unix.write dst b at (n - at)) in
      put 0;
      go ()
  in
  go ()

(* A file's mode and times given to its copy, as cp -p does: by descriptors, to the nanosecond; on Windows, the times by
   the path, where two times of 0.0 are now, so that the start of 1970 is a millionth of a second after it. *)
let copy_times src dst dest =
  if not Sys.win32 then copy_meta (fd_number src) (fd_number dst)
  else
    let st = Unix.fstat src in
    Unix.utimes dest (if st.st_atime = 0.0 && st.st_mtime = 0.0 then 1e-6 else st.st_atime) st.st_mtime

(* The bytes of a file into another, with its mode and its times, as cp -p does: the copy is opened, then seen to be no
   other name of the same file before it is emptied, so that no byte is lost; a folder is refused before, and so is
   what is no file, a pipe, a device or a socket, which the source is opened without waiting for (O_NONBLOCK), then seen
   to be: a pipe, even one put at its path after a check, never holds the program. A link is copied as the file it
   leads to. With [fresh], the copy is made only new. *)
let copy_file ?fresh ctx from dest =
  let src = opened ctx Read from (if Sys.win32 then [ Unix.O_RDONLY ] else [ Unix.O_RDONLY; O_NONBLOCK ]) in
  using src (fun () ->
      let st = Unix.fstat src in
      if st.st_kind = Unix.S_DIR then raise (Unix.Unix_error (Unix.EISDIR, "copy", from));
      if st.st_kind <> Unix.S_REG then raise (Unix.Unix_error (Unix.EOPNOTSUPP, "copy", from));
      if not Sys.win32 then Unix.clear_nonblock src;
      let dst = open_write ~mode:st.st_perm ?fresh ~trunc:false ctx dest [] in
      using dst (fun () ->
          let d = Unix.fstat dst in
          if d.st_dev = st.st_dev && d.st_ino = st.st_ino then raise (Unix.Unix_error (Unix.EINVAL, "copy", dest));
          cut dst;
          copy_bytes src dst;
          copy_times src dst dest));
  Missing

(* A name that no one can know before it is made, for a file or a link made in a folder, then renamed to its own. *)
let temp_name () =
  let r = Lazy.force rand in
  Printf.sprintf ".cesia-%08x%08x.tmp" (Random.State.bits r) (Random.State.bits r)

(* [make] makes an entry at a name of its own in the open folder [d], which then takes the place of [name]: what was
   there stays whole until the new one is; a link there is replaced, never written through. A name taken is drawn
   again. *)
let placed d name make =
  let rec go tries =
    let tmp = temp_name () in
    match make tmp with
    | exception Unix.Unix_error (Unix.EEXIST, _, _) when tries > 0 -> go (tries - 1)
    | exception e -> (try unlink_at d tmp false with Unix.Unix_error _ -> ()); raise e
    | () -> (try rename_at d tmp name with e -> (try unlink_at d tmp false with Unix.Unix_error _ -> ()); raise e)
  in
  go 8

(* A folder of a copy: its descriptors in the source and in the copy, -1 once closed; what they are, to know them again;
   its name in the one above; the names it holds that are left. *)
type pair = {
  mutable src : int;
  src_id : int * int;
  mutable dst : int;
  dst_id : int * int;
  entry : string;
  mutable todo : string list;
}

(* Is the folder open as [fd] the folder [id], or inside it? Its folders above, by .., up to the root, where .. is
   itself; one that can't be opened ends the search. *)
let within fd id =
  let rec up fd here =
    match open_at fd ".." (o_path lor o_dir) 0 with
    | exception Unix.Unix_error _ -> false
    | parent ->
      let there = try ident parent with Unix.Unix_error _ -> here in
      let found = there = id in
      if found || there = here then (Unix.close (fd_of parent); found)
      else Fun.protect ~finally:(fun () -> Unix.close (fd_of parent)) (fun () -> up parent there)
  in
  ident fd = id || up fd (ident fd)

(* On Linux and macOS, by descriptors on both sides, never by paths made again, never through a link: each folder of the
   source opened from the one above it, its names read once, each opened so too (O_NOFOLLOW | O_NONBLOCK): a folder
   entered, a file copied, a link made again with the same text; a pipe, a device or a socket is refused, as no file to
   copy. In the copy, each folder is made, the person's alone while it fills, or taken as it is there, then opened, never
   through a link; each file and link is made at a name of its own, then renamed to its name, which replaces what was
   there. A folder takes its mode and its times once all it holds is in, the deepest first. The copy itself is never
   entered as a folder of the source, as when another program moves it there meanwhile. It walks with a list, and keeps
   the last 32 folders of each side open: one above them is opened again from below by .., and must be the folder it
   left. The first failure raises Unix_error, with the paths of the entry that failed, from [shown] and to [shown_to];
   what went before stays. *)
let copy_walk sfd dfd shown shown_to =
  let stack = ref [] in
  let close l =
    if l.src >= 0 then (Unix.close (fd_of l.src); l.src <- -1);
    if l.dst >= 0 then (Unix.close (fd_of l.dst); l.dst <- -1)
  in
  let step extra f =
    try f ()
    with Unix.Unix_error (e, _, _) ->
      let below = List.rev (List.filter_map (fun l -> if l.entry = "" then None else Some l.entry) !stack) @ extra in
      List.iter close !stack;
      raise (Unix.Unix_error (e, String.concat "/" (shown :: below), String.concat "/" (shown_to :: below)))
  in
  let top = { src = sfd; src_id = ident sfd; dst = dfd; dst_id = ident dfd; entry = ""; todo = [] } in
  stack := [ top ];
  step [] (fun () ->
      if top.dst_id = top.src_id then raise (Unix.Unix_error (Unix.EINVAL, "", ""));
      top.todo <- names_at sfd);
  (* An entry of the folder [l]: a folder to enter, as Some of it; a file or a link copied. *)
  let enter l name =
    match open_at l.src name (o_nofollow lor o_nonblock) 0 with
    | exception Unix.Unix_error ((Unix.ELOOP | Unix.EMLINK), _, _) ->
      let target = readlink_at l.src name in
      placed l.dst name (fun tmp -> symlink_at target l.dst tmp);
      None
    | fd ->
      let d = ref (-1) in
      try
        let st = Unix.fstat (fd_of fd) in
        match st.st_kind with
        | Unix.S_DIR ->
          if (st.st_dev, st.st_ino) = top.dst_id then raise (Unix.Unix_error (Unix.EINVAL, "", ""));
          (try mkdir_at l.dst name 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
          d := open_dir l.dst name;
          Some { src = fd; src_id = st.st_dev, st.st_ino; dst = !d; dst_id = ident !d; entry = name; todo = names_at fd }
        | Unix.S_REG ->
          placed l.dst name (fun tmp ->
              let out = fd_of (open_at l.dst tmp (o_write lor o_create lor o_excl lor o_nofollow) 0o600) in
              using out (fun () -> copy_bytes (fd_of fd) out; copy_meta fd (fd_number out)));
          Unix.close (fd_of fd);
          None
        | _ -> raise (Unix.Unix_error (Unix.EOPNOTSUPP, "", ""))
      with e -> Unix.close (fd_of fd); (if !d >= 0 then Unix.close (fd_of !d)); raise e
  in
  while !stack <> [] do
    match !stack with
    | [] -> ()
    | l :: rest ->
      match l.todo with
      | name :: more ->
        l.todo <- more;
        Option.iter
          (fun child -> stack := child :: !stack; Option.iter close (List.nth_opt !stack 32))
          (step [ name ] (fun () -> enter l name))
      | [] ->
        step [] (fun () ->
            (match rest with
             | up :: _ when up.src < 0 ->
               up.src <- open_dir l.src "..";
               up.dst <- open_dir l.dst "..";
               if ident up.src <> up.src_id || ident up.dst <> up.dst_id then raise (Unix.Unix_error (Unix.EAGAIN, "", ""))
             | _ -> ());
            copy_meta l.src l.dst);
        close l;
        stack := rest
  done

(* Windows has no openat in OCaml: there the copy goes by paths, and enters a folder only if it is where its path leads,
   as remove_paths does; a folder swapped for a link between that check and the next step can still lead it out. *)
let rec copy_paths from dest =
  let st = Unix.lstat from in
  let place make =
    let tmp = Filename.concat (Filename.dirname dest) (temp_name ()) in
    make tmp;
    Unix.rename tmp dest;
    if st.st_kind <> Unix.S_LNK then (Unix.utimes dest st.st_atime st.st_mtime; Unix.chmod dest st.st_perm)
  in
  match st.st_kind with
  | Unix.S_DIR when plain_dir from ->
    (try Unix.mkdir dest 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) when Sys.is_directory dest -> ());
    Array.iter (fun n -> copy_paths (Filename.concat from n) (Filename.concat dest n)) (Sys.readdir from);
    Unix.utimes dest st.st_atime st.st_mtime;
    Unix.chmod dest st.st_perm
  | Unix.S_REG ->
    place (fun tmp ->
        with_fd from [ O_RDONLY ] (fun src -> with_fd ~perm:0o600 tmp [ O_WRONLY; O_CREAT; O_EXCL ] (copy_bytes src)))
  | Unix.S_LNK -> place (Unix.symlink (Unix.readlink from))
  | _ -> raise (Unix.Unix_error (Unix.EOPNOTSUPP, "copy", from))

(* sys.CopyTree: a folder, never a link, and all it holds, into a folder made or one that is there. [from] is opened
   then walked, and [dest] made or opened, each by its name in the folder that holds it, checked as sys.RemoveTree's
   path is. *)
let copy_tree ctx from dest =
  if Sys.win32 then
    try
      if (Unix.lstat from).st_kind <> Unix.S_DIR || not (plain_dir from) then raise (Unix.Unix_error (Unix.ENOTDIR, "", from));
      copy_paths from dest
    with Unix.Unix_error (e, _, at) -> raise (Unix.Unix_error (e, at, ""))
  else
    (* A link where a folder is asked is no folder, whatever the system says of it. *)
    let fail e = raise (Unix.Unix_error ((match e with Unix.ELOOP | Unix.EMLINK -> Unix.ENOTDIR | e -> e), from, dest)) in
    let sfd = try through ~name:true ctx Read from (fun p -> open_dir (-1) p) with Unix.Unix_error (e, _, _) -> fail e in
    (* The copy made in the source, or in a folder of it, is refused before anything is made. *)
    let dfd =
      try
        through ~name:true ctx Write dest (fun p ->
            let up = fd_of (open_at (-1) (Filename.dirname p) (o_path lor o_dir) 0) and base = Filename.basename p in
            using up (fun () ->
                if within (fd_number up) (ident sfd) then raise (Unix.Unix_error (Unix.EINVAL, "", ""));
                (try mkdir_at (fd_number up) base 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
                open_dir (fd_number up) base))
      with e -> Unix.close (fd_of sfd); (match e with Unix.Unix_error (e, _, _) -> fail e | e -> raise e)
    in
    copy_walk sfd dfd from dest

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

(* Is the optional argument [k] given, neither absent nor missing? *)
let given (a : t array) k = k < Array.length a && match a.(k) with Undef | Missing -> false | _ -> true

(* A group, as sys.Stat gives it: a number the system takes for one, not -1, which means none to chown. *)
let group_arg ctx name v =
  match v with
  | Int n when n >= 0 && n < 0xFFFFFFFF -> n
  | v -> Runtime.fail ctx Type (Messages.need_group name (Value.describe v))

(* [below]: the check of the path waits for the act, as [path_arg] says; a panic before it, as for an argument of
   another type, comes after the check, which stops the program first when the path is denied, as it did before. *)
let on_path ?params ?least ?name:link ?(below = false) fn perm verb arity f =
  fn,
  Native.nat ?params ~result:true fn (Option.value least ~default:arity) arity (fun ctx a ->
      let path = path_arg ?name:link ~below ctx fn perm a.(0) in
      let waits = below && fast ctx perm in
      attempt ctx verb path (fun () ->
          try f ctx path a
          with e when waits && (match e with Unix.Unix_error _ -> false | _ -> true) ->
            Runtime.check_perm ?name:link ctx perm (Some path);
            raise e))

let natives =
  [ on_path ~below:true "Read" Read "read" 1 (fun ctx path _ -> read_all ctx path);
    on_path ~params:[| "path"; "text"; "sync"; "private"; "mode"; "group" |] ~least:2 ~below:true "Write" Write "write" 6
      (fun ctx path a ->
         let sync = Native.flag_arg ctx "sync" a 2 and text = Native.text_arg ctx "Write" a.(1) in
         let mode = if given a 4 then Some (mode_arg ctx "Write" a.(4)) else None in
         let group = if given a 5 then Some (group_arg ctx "Write" a.(5)) else None in
         if Native.flag_arg ctx "private" a 3 then begin
           Option.iter (fun m -> if m land 0o077 <> 0 then Runtime.fail ctx Type (Messages.private_mode m)) mode;
           through ~name:true ctx Write path (fun p -> write_private ~sync ?mode ?group p text)
         end
         else write_all ~sync ?mode ?group ~trunc:true ctx path [] text);
    on_path ~below:true "Append" Write "append to" 2 (fun ctx path a ->
        write_all ~trunc:false ctx path [ Unix.O_APPEND ] (Native.text_arg ctx "Append" a.(1)));
    on_path ~below:true "List" Read "list" 1 (fun ctx path _ -> list_dir ctx path);

    on_path ~name:true ~below:true "Remove" Write "remove" 1 (fun ctx path _ -> through ~name:true ctx Write path remove);
    (* What failed deep inside is the path named. *)
    "RemoveTree",
    Native.nat ~result:true "RemoveTree" 1 1 (fun ctx a ->
        let path = path_arg ~name:true ~below:true ctx "RemoveTree" Write a.(0) in
        match through ~name:true ctx Write path (tree ~shown:path) with
        | () -> Value.ok ctx.w Missing
        | exception Unix.Unix_error (e, _, at) -> failed ctx "remove" (if at = "" then path else at) e);
    (* What failed deep inside is named, in both trees. *)
    "CopyTree",
    Native.nat ~params:[| "from"; "to" |] ~result:true "CopyTree" 2 2 (fun ctx a ->
        let from = path_arg ~name:true ctx "CopyTree" Read a.(0) in
        let dest = path_arg ~name:true ctx "CopyTree" Write a.(1) in
        match copy_tree ctx from dest with
        | () -> Value.ok ctx.w Missing
        | exception Unix.Unix_error (e, at, into) -> failed ctx "copy" (if into = "" then at else at ^ " to " ^ into) e);
    on_path "Stat" Read "read" 1 (fun _ path _ ->
        let s = Unix.stat path in
        Trie.record stat_keys
          [| Int s.st_size; Float s.st_mtime; Value.of_bool (s.st_kind = Unix.S_DIR);
             Value.of_bool (s.st_kind = Unix.S_REG); Value.of_bool ((Unix.lstat path).st_kind = Unix.S_LNK); Int s.st_perm;
             Int s.st_uid; Int s.st_gid |]);
    "Copy",
    Native.nat ~params:[| "from"; "to"; "new" |] ~result:true "Copy" 2 3 (fun ctx a ->
        let from = path_arg ctx "Copy" Read a.(0) in
        let fresh = Native.flag_arg ctx "new" a 2 in
        let dest = path_arg ~name:fresh ctx "Copy" Write a.(1) in
        attempt ctx "copy" from (fun () -> copy_file ~fresh ctx from dest));
    on_path ~below:true "Chmod" Write "change the mode of" 2 (fun ctx path a ->
        let mode = mode_arg ctx "Chmod" a.(1) in
        on_open ctx Write path (fun p -> Unix.chmod p mode);
        Missing);
    on_path ~below:true "SetModified" Write "change the time of" 2 (fun ctx path a ->
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
    on_path ~name:true ~below:true "ReadLink" Read "read the link" 1 (fun ctx path _ ->
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
