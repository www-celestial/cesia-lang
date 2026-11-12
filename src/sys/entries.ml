(* An entry larger than this is neither read nor written; [limit] bounds them all. *)
let largest = 64 lsl 20
let limit = 256 lsl 20
let day = 86400.

(* The person's own and no one else's: on Windows, the folder of the person is. *)
let mine (st : Unix.stats) = Sys.win32 || (st.st_uid = Unix.getuid () && st.st_perm land 0o077 = 0)

let folder =
  lazy
    (let base =
       match Sys.getenv_opt "XDG_CACHE_HOME", Sys.getenv_opt "HOME" with
       | Some d, _ when d <> "" -> Some d
       | _, Some h when h <> "" -> Some (Filename.concat h ".cache")
       | _ -> None
     in
     let rec make d =
       if not (Sys.file_exists d) then begin
         make (Filename.dirname d);
         try Unix.mkdir d 0o700 with Unix.Unix_error _ -> ()
       end
     in
     Option.bind base (fun base ->
         let dir = Filename.concat (Filename.concat base "cesia") "load" in
         make dir;
         match Unix.lstat dir with
         | st when st.st_kind = Unix.S_DIR && mine st -> Some dir
         | _ | (exception Unix.Unix_error _) -> None))

let read name =
  match Lazy.force folder with
  | None -> None
  | Some dir ->
    let path = Filename.concat dir name in
    try
      let seen = Unix.lstat path in
      if seen.st_kind <> Unix.S_REG || (not (mine seen)) || seen.st_size > largest then None
      else
        let fd = Unix.openfile path [ O_RDONLY; O_CLOEXEC ] 0 in
        Fun.protect ~finally:(fun () -> Unix.close fd) @@ fun () ->
        let st = Unix.fstat fd in
        (* The file opened is the one looked at, not a link put in its place since. *)
        if st.st_dev <> seen.st_dev || st.st_ino <> seen.st_ino then None
        else begin
          let b = Bytes.create st.st_size in
          let rec fill i =
            if i < st.st_size then match Unix.read fd b i (st.st_size - i) with 0 -> raise End_of_file | n -> fill (i + n)
          in
          fill 0;
          (* An entry in use stays among the newest, for the limit. *)
          if st.st_mtime < Unix.time () -. day then (try Unix.utimes path 0. 0. with Unix.Unix_error _ -> ());
          Some (Bytes.unsafe_to_string b)
        end
    with Unix.Unix_error _ | End_of_file -> None

let prune ~limit dir =
  match Sys.readdir dir with
  | exception Sys_error _ -> ()
  | names ->
    let now = Unix.time () in
    let entry name =
      let path = Filename.concat dir name in
      match Unix.lstat path with
      | st when st.st_kind = Unix.S_REG && Filename.check_suffix name ".tmp" ->
        if st.st_mtime < now -. day then (try Unix.unlink path with Unix.Unix_error _ -> ());
        None
      | st when st.st_kind = Unix.S_REG -> Some (st.st_mtime, st.st_size, path)
      | _ | (exception Unix.Unix_error _) -> None
    in
    let entries = List.filter_map entry (Array.to_list names) in
    let total = List.fold_left (fun n (_, size, _) -> n + size) 0 entries in
    if total > limit then
      ignore
        (List.fold_left
           (fun left (_, size, path) ->
              if left <= limit / 2 then left else try Unix.unlink path; left - size with Unix.Unix_error _ -> left)
           total (List.sort compare entries))

let pruned = ref false
let written = ref 0

let write name data =
  match Lazy.force folder with
  | Some dir when String.length data <= largest ->
    if not !pruned then (pruned := true; prune ~limit dir);
    incr written;
    let tmp = Filename.concat dir (Printf.sprintf "%s.%d.%d.tmp" name (Unix.getpid ()) !written) in
    (try
       (* A new file of the person's alone: O_EXCL follows no link and takes no file already there. *)
       let fd = Unix.openfile tmp [ O_WRONLY; O_CREAT; O_EXCL; O_CLOEXEC ] 0o600 in
       Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
           let n = String.length data in
           let rec put i = if i < n then put (i + Unix.write_substring fd data i (n - i)) in
           put 0);
       (* The old entry goes first: a file renamed over another makes some file systems, btrfs, write it to the disk
          at once, about 8 ms. *)
       (try Unix.unlink (Filename.concat dir name) with Unix.Unix_error _ -> ());
       Unix.rename tmp (Filename.concat dir name)
     with Unix.Unix_error _ -> (try Unix.unlink tmp with Unix.Unix_error _ -> ()))
  | _ -> ()

let store build = { Cesia.Cache.build; read; write }

let after save =
  flush stdout;
  flush stderr;
  match Unix.fork () with
  | 0 ->
    (try
       ignore (Unix.setsid ());
       (* A copy that a lock of another thread, copied with it, would hold forever ends anyway. *)
       Sys.set_signal Sys.sigalrm Sys.Signal_default;
       ignore (Unix.alarm 10);
       let null = Unix.openfile "/dev/null" [ O_RDWR ] 0 in
       List.iter (Unix.dup2 null) [ Unix.stdin; Unix.stdout; Unix.stderr ];
       save ()
     with _ -> ());
    Unix._exit 0
  | _ -> ()
  | exception (Unix.Unix_error _ | Failure _ | Invalid_argument _) -> ()
