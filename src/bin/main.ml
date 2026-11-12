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
  | "native" -> Some Types.Native
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

(* The errors are shown each one once, since the files of a package give the same one. Returns the paths that still
   fail. *)
let reload_all (w : Types.world) paths =
  let failed = Loader.reload_all w paths in
  List.iter w.err (List.sort_uniq compare (List.map snd failed));
  List.map fst failed

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
  uncatch Sys.sighup;
  (* A stop signal means stop, not wait for the next change. *)
  if stopped () then exit code;
  while changed stamps (file :: Loader.watched w) = [] do
    Unix.sleepf poll_period
  done;
  watch o file rest

(* --workers N, or cores for one per logical core: the number of workers of a server. *)
let parse_workers v =
  match v, int_of_string_opt v with
  | "cores", _ -> Domain.recommended_domain_count ()
  | _, Some n when n >= 1 && n <= 1024 -> n
  | _ -> bad_option (Messages.invalid_workers v)

(* The command line of a worker: this one without its --workers. What follows the file is the program's own. *)
let rec without_workers = function
  | "--workers" :: _ :: rest -> without_workers rest
  | (("--allow" | "--limit" | "--seed" | "--debugger") as flag) :: v :: rest -> flag :: v :: without_workers rest
  | flag :: rest when String.starts_with ~prefix:"--" flag -> flag :: without_workers rest
  | rest -> rest

let run args =
  let watching = ref false and workers = ref None in
  let rec options (o : Runtime.options) = function
    | "--no-spec" :: rest -> options { o with o_no_spec = true } rest
    | "--no-jit" :: rest ->
      Tier.mode := Tier.off;
      options o rest
    | "--watch" :: rest ->
      watching := true;
      options o rest
    | "--workers" :: v :: rest ->
      workers := Some (parse_workers v);
      options o rest
    | "--allow" :: v :: rest -> options { o with o_grants = parse_allow o.o_grants v } rest
    | "--limit" :: v :: rest -> options { o with o_limits = parse_limit o.o_limits v } rest
    | "--seed" :: v :: rest ->
      (match int_of_string_opt v with
       | Some n -> Rand.set_seed n
       | None -> bad_option (Messages.invalid_seed v));
      options o rest
    | "--debugger" :: name :: rest ->
      let g = o.o_grants in
      options { o with o_debugger = Some name; o_grants = { g with perms = (Types.Debug, None) :: g.perms } } rest
    | "--repl" :: rest ->
      (* The prompt runs beside the program and may replace its functions, as a reload does. *)
      Tier.watching := true;
      let g = o.o_grants in
      options { o with o_repl = true; o_grants = { g with perms = (Types.Debug, None) :: g.perms } } rest
    | "--cells" :: rest ->
      (* std/cells starts it: the cells run as the prompt runs code, without the hooks of a debugger. *)
      let g = o.o_grants in
      options { o with o_cells = true; o_grants = { g with perms = (Types.Debug, None) :: g.perms } } rest
    | file :: rest when not (String.starts_with ~prefix:"--" file) -> o, file, rest
    | [] when o.o_repl -> o, "", []
    | _ -> usage ()
  in
  let o, file, rest = options (with_default_memory Runtime.default_options) args in
  let readable =
    file = ""
    || Package.files file <> []
    || (Sys.file_exists file && (not (Sys.is_directory file))
        && (try In_channel.with_open_bin file ignore; true with Sys_error _ -> false))
  in
  if not readable then bad_option (Messages.cant_read file);
  if !workers <> None && !watching then bad_option Messages.workers_watch;
  if !workers <> None && Sys.win32 then bad_option Messages.workers_windows;
  if !watching then begin
    Tier.watching := true;
    watch { o with o_period = watch_period } file rest
  end
  else begin
    let w = Runtime.create_world o in
    let argv = Array.of_list (Sys.executable_name :: "run" :: without_workers args) in
    let (_ : unit -> bool) = Cesia_sys.Sys_modules.register ?workers:(Option.map (fun n -> n, argv) !workers) w in
    exit (Loader.run_file w file rest)
  end

(* A plugin beside the binary, found from the binary itself with its links followed: in the lib/ of a release (with its
   licenses/Cesia.txt, as the C libraries), or in src/DIR/ of a build. [Error] says why it didn't load. *)
let load_plugin ?global dir plugin =
  let found =
    match Unix.realpath Sys.executable_name with
    | exception Unix.Unix_error _ -> None
    | exe ->
      let bin = Filename.dirname exe in
      let up = Filename.dirname bin in
      let lib = Filename.concat up "lib" and build = Filename.concat (Filename.concat up dir) plugin in
      if Filename.basename bin <> "bin" then None
      else if Sys.file_exists (Filename.concat lib "licenses/Cesia.txt") then Some (Filename.concat lib plugin)
      else if Sys.file_exists build then Some build
      else None
  in
  match found with
  | None -> Error ("no " ^ plugin ^ " beside the binary")
  | Some path -> Result.map_error (fun m -> path ^ ": " ^ m) (Cesia_sys.Plugin.load ?global path)

(* file.ce:isName is one test of a file; the last : before a test name, so C:\ stays a path. *)
let one_test arg =
  match String.rindex_opt arg ':' with
  | Some i when Testing.is_test (String.sub arg (i + 1) (String.length arg - i - 1)) ->
    String.sub arg 0 i, Some (String.sub arg (i + 1) (String.length arg - i - 1))
  | _ -> arg, None

(* What each tool may touch: see src/tools/. *)
let tool_grants = function
  | "pkg" -> "read,write,exec=git,env=HOME,env=XDG_CACHE_HOME"
  | "check" | "lsp" -> "read"
  | "fmt" -> "read,write"
  | _ -> "read,write,net,exec,env=HOME,env=CESIA_RELEASES,ffi=ssl,ffi=crypto,debug"

let tool ?(grants = "") name args =
  let o = with_default_memory Runtime.default_options in
  let grants = if grants = "" then tool_grants name else grants in
  let w = Runtime.create_world { o with o_grants = parse_allow o.o_grants grants } in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  Loader.run_tool w name args

let worker = ref false
let update = ref false

(* A test may read the project, write in its Temp folder, listen on this machine and connect to its own listeners; [test]
   of cesia.toml and --allow give more. Each grant stays whole: a path can hold a comma. *)
let test_grants root dir (config : Project.test) allow =
  let here = if Runtime.inside root (Sys.getcwd ()) then [ Types.Read, Some "." ] else [] in
  let base = { Types.all = false; perms = Types.[ Read, Some root; Read, Some dir; Write, Some dir; Net, Some "own" ] @ here } in
  List.fold_left (fun g item -> parse_allow g item) base (config.allow @ allow)

(* Several units go to workers, through src/tools/test.ce: each one a cesia test --worker of its own, as many at once as the
   cores, the units of [test] serial alone after the others. *)
let in_workers ~root ~seed ~cases ~no_spec ~allow ~timeout ~serial units =
  let flags =
    [ "--seed"; string_of_int seed; "--cases"; string_of_int cases ] @ (if no_spec then [ "--no-spec" ] else [])
    @ (if !update then [ "--update" ] else [])
    @ List.concat_map (fun a -> [ "--allow"; a ]) allow
  in
  let alone u =
    List.exists (fun s -> let s = Package.absolute (Filename.concat root s) and u = Package.absolute u in
                  u = s || String.starts_with ~prefix:(s ^ "/") u) serial
  in
  let together, after = List.partition (fun u -> not (alone u)) units in
  let args =
    Sys.executable_name :: Printf.sprintf "%g" timeout :: string_of_int (Par.cores ()) :: flags
    @ ("--" :: together) @ ("--serial" :: after)
  in
  tool ~grants:("exec=" ^ Sys.executable_name) "test" args

let test args =
  let rec options (o : Runtime.options) seed cases allow paths = function
    | "--worker" :: rest ->
      worker := true;
      options o seed cases allow paths rest
    | "--no-spec" :: rest -> options { o with o_no_spec = true } seed cases allow paths rest
    | "--update" :: rest ->
      update := true;
      options o seed cases allow paths rest
    | "--seed" :: v :: rest ->
      (match int_of_string_opt v with
       | Some n -> options o (Some n) cases allow paths rest
       | None -> bad_option (Messages.invalid_seed v))
    | "--cases" :: v :: rest -> options o seed (parse_count v) allow paths rest
    | "--allow" :: v :: rest -> options o seed cases (allow @ [ v ]) paths rest
    | p :: rest when not (String.starts_with ~prefix:"--" p) -> options o seed cases allow (p :: paths) rest
    | [] -> o, seed, cases, allow, paths
    | _ -> usage ()
  in
  let o, seed, cases, allow, paths = options (with_default_memory Runtime.default_options) None 100 [] [] args in
  let path, only = match paths with [] -> ".", None | [ p ] -> one_test p | _ -> usage () in
  if not (Sys.file_exists path) then usage ();
  (* A new seed each run, std/random's, so that each run tries new cases; --seed gives the numbers of a run again. *)
  Option.iter Rand.set_seed seed;
  let seed = Rand.seed () in
  let root = Package.root_of path in
  let config = Project.test_config root in
  (* The run's folder, made by the first Temp: random, so that no other program has it ready, and 0700. *)
  Random.self_init ();
  let dir = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "cesia-test-%d-%06x" (Unix.getpid ()) (Random.bits () land 0xFFFFFF)) in
  (* The runner is a plugin beside the binary: programs never pay for its code. *)
  let t =
    match load_plugin "testing" "cesia_testing.cmxs", !Testing.runner with
    | Ok (), Some t -> t
    | Error m, _ -> bad_option (Messages.no_test_plugin m)
    | Ok (), None -> bad_option (Messages.no_test_plugin "it gave no runner")
  in
  let units = if !worker || only <> None then [] else try t.units path with Sys_error m -> bad_option m in
  if List.length units > 1 then
    exit (in_workers ~root ~seed ~cases ~no_spec:o.o_no_spec ~allow ~timeout:config.timeout ~serial:config.serial units);
  (* A worker shares the memory with the others. *)
  let o = if !worker then { o with o_limits = { o.o_limits with memory_words = o.o_limits.memory_words / Par.cores () } } else o in
  let w = Runtime.create_world { o with o_grants = test_grants root dir config allow } in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register ~tick:(poll_period, t.tick) ~reset:t.reset w in
  exit
    (t.run w
       { path; cases; only; worker = !worker; update = !update; dir; timeout = config.timeout; clock = Unix.gettimeofday;
         remove = Cesia_sys.Fs.remove_tree })

let doc args =
  let w = Runtime.create_world Runtime.default_options in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  exit
    (Loader.guarded w (fun _ ->
         Loader.init w;
         Docs.command ~home:(Loader.home w) w args))

(* cesia doc --site [folder] [--open]: the site of the project here, in its site/, or else of Cesia, in the cache. The tool
   gets the root of the project, the folder, the cache and the folder where the programs of the pages run, all from the top
   of the file system. Those programs run in the project's .cesia/site, as files of the project wherever the folder is, so
   that their uses find its src/ and deps/; out of any project, in the folder. The tool writes only there, runs only this
   Cesia, and opens the page with the browser of the system. *)
let site args =
  let home = Option.value (Sys.getenv_opt "HOME") ~default:"." in
  let cache = match Sys.getenv_opt "XDG_CACHE_HOME" with Some d when d <> "" -> d | _ -> Filename.concat home ".cache" in
  let cache = Filename.concat cache "cesia/site" in
  let root = Package.root_of "." in
  let project = Sys.file_exists (Filename.concat root Package.project_file) in
  let folder =
    match List.filter (( <> ) "--open") args with
    | [ f ] when f <> "" && f.[0] <> '-' -> Package.absolute f
    | [] when project -> Filename.concat root "site"
    | [] -> Filename.concat cache Version.number
    | _ -> usage ()
  in
  let runs = if project then Filename.concat (Filename.concat root ".cesia") "site" else Filename.concat folder ".run" in
  let opener = if Sys.win32 then "cmd" else if Sys.file_exists "/System/Library/CoreServices" then "open" else "xdg-open" in
  let grants =
    String.concat ","
      [ "read"; "write=" ^ folder; "write=" ^ cache; "write=" ^ runs; "exec=" ^ Sys.executable_name; "exec=" ^ opener;
        "env=CESIA_CORES" ]
  in
  exit (tool ~grants "site" (root :: folder :: cache :: runs :: List.filter (( = ) "--open") args))

(* The project, then its std/ through the tool that keeps it: one way to write std/ and cesia.lock. *)
let create name =
  Project.create name;
  Sys.chdir name;
  let code = tool "pkg" [ "install" ] in
  if code = 0 then print_endline (Messages.project_created name);
  exit code

(* The JIT, loaded at the first unit that gets hot, never at start-up; missing or refused, programs run interpreted, and
   CESIA_JIT_SHOW says why. *)
let load_jit () =
  let show m = if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ m) in
  match load_plugin "jit" "cesia_jit.cmxs" with Ok () -> show "loaded" | Error m -> show m

(* The tag of the engines of native packages that this build loads, from its compiler: 1-ocaml5.5.0+fp-linux-x86_64. *)
let engine_suffix () =
  let system = if Sys.win32 then "windows" else if Arch.system = "macosx" then "macos" else Arch.system in
  let fp = if Arch.fp then "+fp" else "" and flambda = if Arch.flambda then "+flambda" else "" in
  Printf.sprintf "1-ocaml%s%s%s-%s-%s" Arch.ocaml fp flambda system (if Arch.name = "amd64" then "x86_64" else Arch.name)

(* The plugin of Cesia_v1, once, its code open to the engines: it loads them. *)
let interface = lazy (load_plugin ~global:true "native" "cesia_native.cmxs")
let load_interface () = Lazy.force interface

(* CESIA_JIT=off or always, for tests; native code otherwise comes to what gets hot. On arm64 the JIT stays off until it
   is tested there: programs run interpreted, with the same results. *)
let jit_mode () =
  Tier.available := Arch.name <> "arm64";
  if (not !Tier.available) && Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline "jit: off on arm64 for now";
  Tier.loader := load_jit;
  Cesia_sys.Sys_modules.sqlite_loader := (fun () -> load_plugin "sqlite" "cesia_sqlite.cmxs");
  Cesia_sys.Sys_modules.debug_loader := (fun () -> load_plugin "debug" "cesia_debug.cmxs");
  Engines.suffix := engine_suffix;
  Engines.interface := load_interface;
  match Sys.getenv_opt "CESIA_JIT" with
  | Some "off" -> Tier.mode := Tier.off
  | Some "always" -> Tier.mode := Tier.always
  | _ -> ()

let () =
  try
    Cache.build := Build.id;
    jit_mode ();
    match Array.to_list Sys.argv with
    | _ :: "version" :: _ -> print_endline Version.text
    | _ :: "run" :: args -> run args
    | _ :: "test" :: args -> test args
    | _ :: "do" :: args -> Project.run args
    | [ _; "new"; name ] -> create name
    | _ :: (("pkg" | "upgrade" | "check" | "fmt") as name) :: args -> exit (tool name args)
    | [ _; "lsp" ] ->
      (* The protocol counts bytes: Windows must not turn a line end into two. *)
      set_binary_mode_out stdout true;
      exit (tool "lsp" [])
    | _ :: "doc" :: "--site" :: args -> site args
    | _ :: "doc" :: args -> doc args
    | _ -> usage ()
  with
  | Stdlib.Exit as e -> raise e
  | e -> internal_error e
