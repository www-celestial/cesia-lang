open Cesia

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
  prerr_endline ("cesia: " ^ text);
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
  { o with o_limits = { o.o_limits with memory_words = Runtime.default_memory (Cesia_sys.Sys_modules.ram ()) } }

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

(* A package can use another, so a failure may only mean that what it needs comes later in the list: what failed is tried
   again as long as something else loads. Only then are the errors shown, each one once, since the files of a package give the
   same one. Returns the paths that still fail. *)
let rec reload_all (w : Types.world) paths =
  let failed =
    List.filter_map
      (fun path ->
         match Loader.reload w path with
         | Ok () -> None
         | Error text -> Some (path, text))
      paths
  in
  if failed <> [] && List.compare_lengths failed paths < 0 then reload_all w (List.map fst failed)
  else begin
    List.iter w.err (List.sort_uniq compare (List.map snd failed));
    List.map fst failed
  end

(* Gives a signal its default action back. One that was ignored from the start stays ignored, as for a background job of
   a script. *)
let uncatch signal =
  match Sys.signal signal Sys.Signal_default with
  | Sys.Signal_ignore -> Sys.set_signal signal Sys.Signal_ignore
  | _ -> ()

let poll_period = 0.05

(* A changed file must be active within 100 ms, even when each step is heavy. *)
let watch_period = 100_000

(* Reloads at the checkpoint; a finished program restarts when a file changes. *)
let rec watch (o : Runtime.options) file rest =
  let w = Runtime.create_world o in
  let stamps = Hashtbl.create 8 in
  ignore (changed stamps [ file ]);
  (* What failed waits for the next change, which may be the one it needs: a retry at each pass would repeat its error. *)
  let failed = ref [] in
  let reload_changed () =
    match changed stamps (Loader.watched w) with
    | [] -> ()
    | paths -> failed := reload_all w (List.sort_uniq compare (paths @ !failed))
  in
  let stopped = Cesia_sys.Sys_modules.register ~tick:(poll_period, reload_changed) ~watching:true w in
  w.on_checkpoint <- (fun _ -> reload_changed ());
  let code = Loader.run_file w file rest in
  (* From here a signal does what it does to any program, so none is lost: one that came earlier is what stopped tells of. *)
  uncatch Sys.sigint;
  uncatch Sys.sigterm;
  (* A stop signal means stop, not wait for the next change. *)
  if stopped () then exit code;
  while changed stamps (file :: Loader.watched w) = [] do
    Unix.sleepf poll_period
  done;
  watch o file rest

let run args =
  let watching = ref false in
  let rec options (o : Runtime.options) = function
    | "--no-spec" :: rest -> options { o with o_no_spec = true } rest
    | "--no-jit" :: rest ->
      Tier.mode := Tier.off;
      options o rest
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
    Package.files file <> []
    || (Sys.file_exists file && (not (Sys.is_directory file))
        && (try In_channel.with_open_bin file ignore; true with Sys_error _ -> false))
  in
  if not readable then bad_option (Messages.cant_read file);
  if !watching then watch { o with o_period = watch_period } file rest
  else begin
    let w = Runtime.create_world o in
    let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
    exit (Loader.run_file w file rest)
  end

let test args =
  let no_spec = List.mem "--no-spec" args in
  let paths = List.filter (fun a -> a <> "--no-spec") args in
  let path = match paths with [] -> "." | [ p ] -> p | _ -> usage () in
  if List.exists (String.starts_with ~prefix:"--") paths || not (Sys.file_exists path) then usage ();
  let w = Runtime.create_world { (with_default_memory Runtime.default_options) with o_no_spec = no_spec } in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  exit (Testrun.run w ~path)

(* An 8 MB minor heap: the boxed floats of the generic path nearly all die young. *)
let tune_gc () = Gc.set { (Gc.get ()) with minor_heap_size = 1 lsl 20 }

let doc args =
  let w = Runtime.create_world Runtime.default_options in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  exit
    (Loader.guarded w (fun _ ->
         Loader.init w;
         Docs.command w args))

(* What each tool may touch: see src/tools/. *)
let tool_grants = function
  | "pkg" -> "read,write,exec=git,env=HOME,env=XDG_CACHE_HOME"
  | _ -> "read,write,net,exec,env=HOME,env=CESIA_RELEASES,ffi=ssl,ffi=crypto,debug"

let tool name args =
  let o = with_default_memory Runtime.default_options in
  let w = Runtime.create_world { o with o_grants = parse_allow o.o_grants (tool_grants name) } in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  Loader.run_tool w name args

(* The project, then its pkg/ through the tool that keeps it: one way to write pkg/ and cesia.lock. *)
let create name =
  Project.create name;
  Sys.chdir name;
  let code = tool "pkg" [ "install" ] in
  if code = 0 then print_endline (Messages.project_created name);
  exit code

(* CESIA_JIT=off or always, for tests; native code otherwise comes to what gets hot. *)
let jit_mode () =
  match Sys.getenv_opt "CESIA_JIT" with
  | Some "off" -> Tier.mode := Tier.off
  | Some "always" -> Tier.mode := Tier.always
  | _ -> ()

let () =
  try
    tune_gc ();
    jit_mode ();
    match Array.to_list Sys.argv with
    | _ :: "version" :: _ -> print_endline Version.text
    | _ :: "run" :: args -> run args
    | _ :: "test" :: args -> test args
    | _ :: "do" :: args -> Project.run args
    | [ _; "new"; name ] -> create name
    | _ :: (("pkg" | "upgrade") as name) :: args -> exit (tool name args)
    | _ :: "doc" :: args -> doc args
    | _ -> usage ()
  with
  | Stdlib.Exit as e -> raise e
  | e -> internal_error e
