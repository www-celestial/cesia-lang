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

type mapped = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(* The compiler's own loads and stores of 8 bytes, which no C backs. *)
external get64 : mapped -> int -> int64 = "%caml_bigstring_get64u"
external set64 : Bytes.t -> int -> int64 -> unit = "%caml_bytes_set64u"

(* [len] bytes of a mapped entry from [off], copied out of it: what is checked is then what is read, whatever another
   process writes into the file meanwhile. The range is checked once; the copy goes 32 bytes at a time. *)
let part (a : mapped) off len =
  if off < 0 || len < 0 || off > Bigarray.Array1.dim a - len then invalid_arg "Entries.part";
  let b = Bytes.create len in
  let i = ref 0 in
  while !i + 32 <= len do
    let j = !i in
    set64 b j (get64 a (off + j));
    set64 b (j + 8) (get64 a (off + j + 8));
    set64 b (j + 16) (get64 a (off + j + 16));
    set64 b (j + 24) (get64 a (off + j + 24));
    i := j + 32
  done;
  for j = !i to len - 1 do Bytes.set b j (Bigarray.Array1.get a (off + j)) done;
  Bytes.unsafe_to_string b

(* An entry mapped, its descriptor closed at once: only the pages read are, and no call of the system reads a body.
   The mapping lasts as long as a body not yet read needs it. Another run unlinks or replaces an entry, never writes it
   in place: on POSIX, the file mapped stays as it was. On Windows, a file mapped can't be deleted or replaced until
   the run ends; no entry is written there today, as [after] can't fork, so none is mapped. *)
let map name =
  match Lazy.force folder with
  | None -> None
  | Some dir ->
    let path = Filename.concat dir name in
    try
      let seen = Unix.lstat path in
      if seen.st_kind <> Unix.S_REG || (not (mine seen)) || seen.st_size > largest || seen.st_size = 0 then None
      else
        let fd = Unix.openfile path [ O_RDONLY; O_CLOEXEC ] 0 in
        Fun.protect ~finally:(fun () -> Unix.close fd) @@ fun () ->
        let st = Unix.fstat fd in
        (* The file opened is the one looked at, not a link put in its place since. *)
        if st.st_dev <> seen.st_dev || st.st_ino <> seen.st_ino || st.st_size = 0 then None
        else begin
          let a = Bigarray.array1_of_genarray (Unix.map_file fd Bigarray.char Bigarray.c_layout false [| st.st_size |]) in
          (* An entry in use stays among the newest, for the limit. *)
          if st.st_mtime < Unix.time () -. day then (try Unix.utimes path 0. 0. with Unix.Unix_error _ -> ());
          Some (st.st_size, part a)
        end
    with Unix.Unix_error _ | Sys_error _ | Failure _ | Invalid_argument _ -> None

let prune ?(adding = 0) ~limit dir =
  match Sys.readdir dir with
  | exception Sys_error _ -> 0
  | names ->
    let now = Unix.time () in
    let entry name =
      let path = Filename.concat dir name in
      match Unix.lstat path with
      | _ when name = "total" -> None
      | st when st.st_kind = Unix.S_REG && Filename.check_suffix name ".tmp" ->
        if st.st_mtime < now -. day then (try Unix.unlink path with Unix.Unix_error _ -> ());
        None
      | st when st.st_kind = Unix.S_REG -> Some (st.st_mtime, st.st_size, path)
      | _ | (exception Unix.Unix_error _) -> None
    in
    let entries = List.filter_map entry (Array.to_list names) in
    let total = List.fold_left (fun n (_, size, _) -> n + size) 0 entries in
    (* With the entry about to be written: a folder just under the limit, whose entries are written again at the same
       size, would else be looked over at each write. *)
    if total + adding <= limit then total
    else
      List.fold_left
        (fun left (_, size, path) ->
           if left <= limit / 2 then left else try Unix.unlink path; left - size with Unix.Unix_error _ -> left)
        total (List.sort compare entries)

(* The bytes written since the folder was last looked over, counted in its file [total] under a lock, so that hundreds
   of runs that end at once don't each read 40,000 entries: the count unknown or past the limit, the folder is pruned
   and counted again. *)
let account ~limit dir n =
  match Unix.openfile (Filename.concat dir "total") [ O_RDWR; O_CREAT; O_CLOEXEC ] 0o600 with
  | exception Unix.Unix_error _ -> false
  | fd ->
    Fun.protect ~finally:(fun () -> Unix.close fd) @@ fun () ->
    try
      Unix.lockf fd F_LOCK 0;
      let b = Bytes.make 8 '\000' in
      let before = if Unix.read fd b 0 8 = 8 then Int64.to_int (Bytes.get_int64_le b 0) else limit in
      (* Compared as [before > limit - n], not [before + n > limit]: a count spoilt near the largest number would wrap. *)
      let after = (if before < 0 || before > limit - n then prune ~adding:n ~limit dir else before) + n in
      Bytes.set_int64_le b 0 (Int64.of_int after);
      Unix.lseek fd 0 SEEK_SET = 0 && Unix.write fd b 0 8 = 8
    with Unix.Unix_error _ -> false

let written = ref 0

let write name data =
  match Lazy.force folder with
  | Some dir when String.length data <= largest && account ~limit dir (String.length data) ->
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

let store build = { Cesia.Cache.build; map; write }

external close_from : int -> unit = "cesia_close_from"

(* The signals a program may have set handlers for: the copy takes none of them. *)
let signals =
  Sys.[ sigint; sigterm; sighup; sigquit; sigpipe; sigalrm; sigchld; sigusr1; sigusr2; sigtstp; sigttin; sigttou; sigvtalrm ]

let after save =
  flush stdout;
  flush stderr;
  Pool.stop ();
  (* The end of the run waits until the copy holds none of its descriptors, when the copy's end of this pipe closes with
     the others: a program started at once finds the port free and the lock free. *)
  match Unix.pipe () with
  | exception Unix.Unix_error _ -> ()
  | closed, closing ->
    match Unix.fork () with
    | 0 ->
      (try
         (* Before anything else, none of the program's descriptors stays open in the copy: a listener stays bound, a
            lock held and the end of a pipe open as long as one of them is. *)
         close_from 3;
         ignore (Unix.setsid ());
         List.iter (fun s -> try Sys.set_signal s Sys.Signal_default with Invalid_argument _ | Sys_error _ -> ()) signals;
         (* A copy that a lock of another thread, copied with it, would hold forever ends anyway. *)
         ignore (Unix.alarm 10);
         let null = Unix.openfile "/dev/null" [ O_RDWR ] 0 in
         List.iter (Unix.dup2 null) [ Unix.stdin; Unix.stdout; Unix.stderr ];
         Unix.close null;
         save ()
       with _ -> ());
      (* No function of the program's end, nor a finalizer, runs a second time. *)
      Unix._exit 0
    | _ ->
      Unix.close closing;
      (try ignore (Unix.read closed (Bytes.create 1) 0 1) with Unix.Unix_error _ -> ());
      Unix.close closed
    | exception (Unix.Unix_error _ | Failure _ | Invalid_argument _) -> Unix.close closing; Unix.close closed
