open Kepler

let usage () =
  prerr_endline Messages.usage;
  exit 2

let internal_error e =
  prerr_endline (Messages.internal (Printexc.to_string e));
  exit 3

let split_list s = List.filter (fun x -> x <> "") (String.split_on_char ',' s)

let perm_of_name = function
  | "read" -> Some Types.Read
  | "write" -> Some Types.Write
  | "net" -> Some Types.Net
  | "exec" -> Some Types.Exec
  | "env" -> Some Types.Env
  | "ffi" -> Some Types.Ffi
  | "debug" -> Some Types.Debug
  | _ -> None

let bad_option text =
  prerr_endline ("kepler: " ^ text);
  exit 2

let parse_allow (grants : Types.grants) s =
  List.fold_left
    (fun (g : Types.grants) item ->
       if item = "all" then { g with all = true }
       else begin
         let name, scope =
           match String.index_opt item '=' with
           | Some i ->
             String.sub item 0 i, Some (String.sub item (i + 1) (String.length item - i - 1))
           | None -> item, None
         in
         if scope = Some "" then bad_option (Messages.invalid_permission item);
         match perm_of_name name with
         | Some p -> { g with perms = (p, scope) :: g.perms }
         | None -> bad_option (Messages.unknown_permission name)
       end)
    grants (split_list s)

(* 512M, 2G, 1000K, or a number of bytes. *)
let parse_size s =
  let n = String.length s in
  let digits, unit =
    if n = 0 then s, 1
    else
      match s.[n - 1] with
      | 'K' -> String.sub s 0 (n - 1), 1024
      | 'M' -> String.sub s 0 (n - 1), 1024 * 1024
      | 'G' -> String.sub s 0 (n - 1), 1024 * 1024 * 1024
      | _ -> s, 1
  in
  match int_of_string_opt digits with
  | Some v when v >= 0 && v <= max_int / unit -> v * unit
  | _ -> bad_option (Messages.invalid_size s)

let parse_count s =
  match int_of_string_opt s with
  | Some v when v > 0 -> v
  | _ -> bad_option (Messages.invalid_limit s)

let parse_limit (l : Types.limits) s =
  List.fold_left
    (fun (l : Types.limits) item ->
       match String.index_opt item '=' with
       | None -> bad_option (Messages.invalid_limit item)
       | Some i ->
         let v = String.sub item (i + 1) (String.length item - i - 1) in
         (match String.sub item 0 i with
          | "steps" -> { l with steps = parse_count v }
          | "memory" -> { l with memory_words = parse_size v / 8 }
          | "depth" -> { l with max_depth = parse_count v }
          | "nesting" -> { l with nesting = parse_count v }
          | name -> bad_option (Messages.unknown_limit name)))
    l (split_list s)

(* 80% of the RAM by default: without a limit, one large array can freeze the machine. *)
let with_default_memory (o : Runtime.options) =
  let meminfo =
    try In_channel.with_open_bin "/proc/meminfo" In_channel.input_all with Sys_error _ -> ""
  in
  { o with o_limits = { o.o_limits with memory_words = Runtime.default_memory meminfo } }

(* What tells that a file has changed. *)
let stamp path =
  match Unix.stat path with
  | st -> Some (st.Unix.st_mtime, st.Unix.st_size, st.Unix.st_ino)
  | exception Unix.Unix_error _ -> None

(* The files changed since the last pass. A missing file is ignored: an editor is probably replacing it, and it will
   be picked up when it returns. *)
let changed stamps paths =
  List.filter
    (fun path ->
       match stamp path, Hashtbl.find_opt stamps path with
       | None, _ -> false
       | Some now, Some before when now = before -> false
       | Some now, before ->
         Hashtbl.replace stamps path now;
         before <> None)
    (List.sort_uniq compare paths)

let poll_period = 0.05

(* A changed file must be active within 100 ms, even when each step is heavy. *)
let watch_period = 100_000

(* Reloads at the checkpoint; a finished program restarts when a file changes. *)
let rec watch (o : Runtime.options) file rest =
  let w = Runtime.create_world o in
  let stamps = Hashtbl.create 8 in
  ignore (changed stamps [ file ]);
  w.on_checkpoint <-
    (fun _ ->
       List.iter
         (fun path ->
            match Loader.reload w path with
            | Ok () -> ()
            | Error text -> w.err text)
         (changed stamps (Loader.watched w)));
  ignore (Loader.run_file w file rest);
  while changed stamps (file :: Loader.watched w) = [] do
    Unix.sleepf poll_period
  done;
  watch o file rest

let run args =
  let watching = ref false in
  let rec options (o : Runtime.options) = function
    | "--no-spec" :: rest -> options { o with o_no_spec = true } rest
    | "--watch" :: rest ->
      watching := true;
      options o rest
    | "--allow" :: v :: rest -> options { o with o_grants = parse_allow o.o_grants v } rest
    | "--limit" :: v :: rest -> options { o with o_limits = parse_limit o.o_limits v } rest
    | "--debugger" :: name :: rest ->
      let g = o.o_grants in
      options { o with o_debugger = Some name; o_grants = { g with perms = (Types.Debug, None) :: g.perms } } rest
    | file :: rest when not (String.starts_with ~prefix:"--" file) -> o, file, rest
    | _ -> usage ()
  in
  let o, file, rest = options (with_default_memory Runtime.default_options) args in
  let readable =
    Sys.file_exists file && (not (Sys.is_directory file))
    && (try In_channel.with_open_bin file ignore; true with Sys_error _ -> false)
  in
  if not readable then bad_option (Messages.cant_read file);
  if !watching then watch { o with o_period = watch_period } file rest
  else exit (Loader.run_file (Runtime.create_world o) file rest)

let test args =
  let no_spec = List.mem "--no-spec" args in
  let paths = List.filter (fun a -> a <> "--no-spec") args in
  let path = match paths with [] -> "." | [ p ] -> p | _ -> usage () in
  if List.exists (String.starts_with ~prefix:"--") paths || not (Sys.file_exists path) then usage ();
  let w = Runtime.create_world { (with_default_memory Runtime.default_options) with o_no_spec = no_spec } in
  exit (Testrun.run w ~path)

(* An 8 MB minor heap: the boxed floats of the generic path nearly all die young. *)
let tune_gc () = Gc.set { (Gc.get ()) with minor_heap_size = 1 lsl 20 }

let () =
  try
    tune_gc ();
    match Array.to_list Sys.argv with
    | _ :: "version" :: _ -> print_endline Version.text
    | _ :: "run" :: args -> run args
    | _ :: "test" :: args -> test args
    | _ -> usage ()
  with
  | Stdlib.Exit as e -> raise e
  | e -> internal_error e
