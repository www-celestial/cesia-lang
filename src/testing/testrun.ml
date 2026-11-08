open Types

type stats = { mutable passed : int; mutable failed : int }

(* [skip] is the root: its std/ and deps/ hold copies, which their own projects test, unless named. A link to a folder is
   never followed: it could lead out of the project, or back up into a loop. A folder that can't be listed is a Sys_error. *)
let source_files ~skip path =
  if Sys.is_directory path then
    let left_out dir n = n = "" || n.[0] = '.' || n = "_build" || ((n = "std" || n = "deps") && Package.absolute dir = skip) in
    match Cesia_sys.Fs.paths ~skip:left_out path with
    | paths -> List.filter (fun p -> Package.is_source p && Sys.file_exists p && not (Sys.is_directory p)) paths
    | exception Unix.Unix_error (e, _, at) -> raise (Sys_error (Messages.io_failure "list" at (Cesia_sys.Fs.reason e)).text)
  else if Package.is_source path then [ path ]
  else []

let in_tests_dir path = List.mem "tests" (String.split_on_char '/' (Filename.dirname path))
let is_test_file path = Package.is_test path || in_tests_dir path

type example = { line : int; code : string; want : [ `Stmt | `Value of string | `Error ] }

let find_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = if i + m > n then None else if String.sub s i m = sub then Some i else go (i + 1) in
  go 0

(* The examples: the indented lines of a documentation, each with its line. *)
let examples src =
  List.map
    (fun (line, text) ->
       let text = String.trim text in
       match find_sub text "-->" with
       | None -> { line; code = text; want = `Stmt }
       | Some k ->
         let code = String.trim (String.sub text 0 k) in
         let r = String.trim (String.sub text (k + 3) (String.length text - k - 3)) in
         { line; code; want = (if r = "error" then `Error else `Value r) })
    (Docs.examples src)

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '$' -> Buffer.add_string b "$$"
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

(* The examples of a file see the modules it uses. *)
let example_source src ex =
  let b = Buffer.create 256 in
  List.iter
    (fun line ->
       if String.starts_with ~prefix:"use " line then begin
         Buffer.add_string b line;
         Buffer.add_char b '\n'
       end)
    (String.split_on_char '\n' src);
  List.iter
    (fun e ->
       Buffer.add_string b
         (match e.want with
          | `Stmt -> e.code
          | `Value r -> Printf.sprintf "docEq(%d, %s, () -> (%s), () -> (%s))" e.line (quote e.code) e.code r
          | `Error -> Printf.sprintf "docErr(%d, %s, () -> (%s))" e.line (quote e.code) e.code);
       Buffer.add_char b '\n')
    ex;
  Buffer.contents b

let native nname n run =
  Native { nname; perm = None; params = [||]; min_args = n; max_args = n; ret_ty = (fun _ -> TA); run; f1 = None; i2 = None; gives_result = false }

let text_arg = function Text s -> s | _ -> ""
let int_arg = function Int i -> i | _ -> 0

(* The text of what stopped a test, an example or the load of a file: a Cesia error, or sys.Exit, which ends no test run. *)
let failure = function
  | Value.Quit code -> Some (Messages.test_exit code)
  | e -> Loader.message_of_error e

let run_examples (ctx : ctx) st path m src =
  let w = ctx.w in
  match examples src with
  | [] -> ()
  | ex ->
    let fail line code detail =
      st.failed <- st.failed + 1;
      print_endline (Printf.sprintf "%s:%d: %s --> %s" path line code detail)
    in
    let check_eq c a =
      let line = int_arg a.(0) and code = text_arg a.(1) in
      let error e = fail line code ("error: " ^ Option.get (failure e)) in
      (match Loader.call_caught c a.(2) [||] with
       | Error e -> error e
       | Ok got ->
         match Loader.call_caught c a.(3) [||] with
         | Error e -> error e
         | Ok want ->
           if Value.equal c got want then st.passed <- st.passed + 1
           else fail line code (Printf.sprintf "%s, got %s" (Value.show c want) (Value.show c got)));
      Missing
    in
    let check_err c a =
      let line = int_arg a.(0) and code = text_arg a.(1) in
      (match Loader.call_caught c a.(2) [||] with
       | Ok v -> fail line code ("error, got " ^ Value.show c v)
       | Error (Value.Kerr _) -> st.passed <- st.passed + 1
       | Error (Value.Quit _ as e) -> fail line code ("error: " ^ Option.get (failure e))
       | Error e -> raise e);
      Missing
    in
    let doc_eq = native "docEq" 4 check_eq and doc_err = native "docErr" 3 check_err in
    let doc_m = Array.length w.modules in
    let helpers =
      { mname = "doc"; path = ""; cells = [| doc_eq; doc_err |]; mnames = [ "docEq", 0; "docErr", 1 ];
        stable = [| true; true |]; host = doc_m; package = [| doc_m |]; uses = [] }
    in
    w.modules <- Array.append w.modules [| helpers |];
    let lookup name =
      match Loader.in_module w doc_m name with
      | Some b -> Some b
      | None ->
        match Loader.in_package w m name with
        | Some b -> Some b
        | None -> Loader.lookup w name
    in
    (try
       let prepared = Loader.prepare ~host:m ctx ~path:(path ^ " (examples)") ~src:(example_source src ex) ~lookup in
       ctx.b <- 0;
       Loader.run_prepared ctx prepared
     with e ->
       match failure e with
       | Some msg ->
         st.failed <- st.failed + 1;
         print_endline (Printf.sprintf "%s:%d: the examples failed: %s" path (List.hd ex).line msg)
       | None -> raise e)

let is_test_name = Verdict.is_test

(* What the verdicts of the tests of the file being run noted: see Verdict. [got.(k)] is the value of note k in the last run of
   its test, with its rank among the notes of that run. *)
type record = { mutable notes : Verdict.note array; mutable got : (t * int) option array; mutable rank : int; mutable floor : int }

let record = { notes = [||]; got = [||]; rank = 0; floor = 0 }

let rewrite fn =
  record.notes <- Verdict.rewrite fn;
  record.got <- Array.make (Array.length record.notes) None

let note =
  Native
    { nname = "#note"; perm = None; params = [||]; min_args = 2; max_args = 2;
      ret_ty = (fun tys -> if Array.length tys > 1 then tys.(1) else TA); f1 = None; i2 = None; gives_result = false;
      run =
        (fun _ a ->
           let k = int_arg a.(0) in
           if k >= 0 && k < Array.length record.got then begin
             record.got.(k) <- Some (Value.share a.(1), record.rank);
             record.rank <- record.rank + 1
           end;
           a.(1)) }

(* A property of test.ForAll failed: the case, the smallest value, the verdict of the property on it, and how to replay. *)
let report_property ctx path line name (f : Props.failure) =
  let where = if f.case = 0 then Messages.test_saved_case else Messages.test_case f.case f.cases in
  print_endline (Printf.sprintf "%s:%d: %s failed %s" path line name (where ^ Messages.test_shrunk f.from f.until));
  let param = Option.value (Verdict.property record.notes record.got ~test:name) ~default:"value" in
  print_endline (Printf.sprintf "  %s = %s" param (Verdict.cut (Value.show ctx f.value)));
  (match f.panic with Some m -> print_endline ("  | " ^ Messages.test_panic m) | None -> ());
  (match Verdict.explain ctx record.notes record.got ~test:name ~prop:true ~floor:record.floor f.value with
   | Some (_, lines) -> List.iter print_endline lines
   | None -> ());
  print_endline ("  " ^ Messages.test_replay path (Rand.seed ()))

(* A failed test: its line, then what its verdict noted, then its snapshot. *)
let rec report ctx path line name v =
  Runtime.flush_out ctx.w;
  verdict ctx path line name v;
  match Props.st.snap_failure with
  | first :: lines -> print_endline ("  " ^ first); List.iter (fun l -> print_endline ("  | " ^ l)) lines
  | [] -> ()

and verdict ctx path line name v =
  let returned () = print_endline (Printf.sprintf "%s:%d: %s returned %s" path line name (Value.show ctx v)) in
  match Props.st.failed with
  | Some f when v == False -> report_property ctx path line name f
  | _ ->
  let failed header = print_endline (Printf.sprintf "%s:%d: %s failed%s" path line name header) in
  match Verdict.explain ctx record.notes record.got ~test:name ~prop:false ~floor:0 v with
  | Some (header, lines) when header <> "" || List.length lines > 1 ->
    if v == False || header <> "" then failed header else returned ();
    List.iter print_endline lines
  | _ -> if Props.st.snap_failure <> [] && v == False then failed "" else returned ()

(* cesia test file.ce:isName runs that test alone; [only_looked] says that its file was looked through, or failed. *)
let only_test = ref None
let only_looked = ref false

(* Set by the binary, which can reach the system: removes a folder without following links; closes the sockets and forgets
   the waiting fibers. *)
let remove = ref (fun (_ : string) -> ())
let reset = ref ignore

(* In a worker: each test is named as it starts. *)
let marked = ref false

(* Did a failed test keep its Temp folder, and with it the run's? *)
let kept = ref false

(* A test past its deadline stops, at a checkpoint or while it waits. *)
let past ctx = if Props.st.clock () > Props.st.deadline then Runtime.fail ctx User (Messages.test_timeout Props.st.timeout)

let tick () =
  if Props.st.clock () > Props.st.deadline then begin
    let m = Messages.test_timeout Props.st.timeout in
    raise (Value.Kerr { kind = User; text = m.text; hint = m.hint; at = -1 })
  end

(* A path as the root sees it, the same from any folder: the name of a test's saved failures. *)
let from_root w path =
  let p = Package.absolute path in
  let r = w.root ^ "/" in
  if String.starts_with ~prefix:r p then String.sub p (String.length r) (String.length p - String.length r) else p

(* The site a test starts from: no line of the program, which a trace leaves out. A test that stops in a loop before any
   call or native shows no place it doesn't know, and its first frame isn't called from a line. *)
let no_place w =
  Vec.push w.sites { sfile = 0; spos = Pos.make 1 1; sfn = ""; sver = None; soff = 0; slive = Bytes.empty; shidden = false }

let run_tests (ctx : ctx) st path (layout : Ast.layout) cells =
  let ran = ref [] in
  let start = no_place ctx.w in
  let runnable (f : Ast.func) = is_test_name f.fname && Array.length f.params = 0 && Lexer.split_method f.fname = None in
  Array.iter
    (fun (k, (f : Ast.func)) ->
       if runnable f && (match !only_test with Some n -> String.equal n f.fname | None -> true) then begin
         let line = Pos.line f.fpos in
         ctx.b <- 0;
         ctx.site <- start;
         Array.fill record.got 0 (Array.length record.got) None;
         (* A worker names each test as it starts, so that cesia test can name the one that stopped answering. *)
         if !marked then begin
           Runtime.flush_out ctx.w;
           print_endline ("\001" ^ path ^ ":" ^ f.fname);
           flush stdout
         end;
         Props.st.root <- ctx.w.root;
         Props.start_test ~path ~file:(from_root ctx.w path) ~test:f.fname;
         ran := f.fname :: !ran;
         record.floor <- 0;
         let finish passed =
           (match Props.st.temp with
            | Some d when passed -> !remove d
            | Some d -> print_endline ("  " ^ Messages.test_temp d); kept := true
            | None -> ());
           Props.st.deadline <- infinity;
           (* No fiber, socket or timer of a test outlives it. *)
           Queue.clear ctx.w.sched.ready;
           !reset ()
         in
         match Compile.call_value ctx ~base:2 cells.(k) [||] with
         | True -> st.passed <- st.passed + 1; finish true
         | v ->
           st.failed <- st.failed + 1;
           report ctx path line f.fname v;
           finish false
         | exception e ->
           match failure e with
           | Some msg ->
             st.failed <- st.failed + 1;
             Runtime.flush_out ctx.w;
             print_endline (Printf.sprintf "%s:%d: %s failed: %s" path line f.fname msg);
             (* Where it stopped, when not on the line of the test itself. *)
             (match e with
              | Value.Kerr { at; _ } when at >= 0 && at < Vec.length ctx.w.sites ->
                (match Runtime.backtrace ctx at with
                 | [ t ] when String.ends_with ~suffix:(Printf.sprintf ":%d)" line) t -> ()
                 | trace -> List.iter (fun t -> print_endline ("  " ^ t)) trace)
              | _ -> ());
             finish false
           | None -> raise e
       end)
    layout.hoisted;
  let tests = List.filter_map (fun (_, (f : Ast.func)) -> if is_test_name f.fname then Some f.fname else None) (Array.to_list layout.hoisted) in
  (* file.ce:isName with a name that no test of the file has: a typo would otherwise pass with no test run. *)
  only_looked := true;
  (match !only_test with
   | Some name when !ran = [] ->
     st.failed <- st.failed + 1;
     let names = List.filter_map (fun (_, f) -> if runnable f then Some f.Ast.fname else None) (Array.to_list layout.hoisted) in
     print_endline (Messages.test_unknown path name names)
   | _ -> ());
  Props.write_snaps path ~ran:!ran ~tests

(* Anything to run in this file? *)
let has_tests path src =
  examples src <> []
  || (is_test_file path
      && List.exists
           (fun l ->
              is_test_name l
              || (String.starts_with ~prefix:"defn " l && is_test_name (String.sub l 5 (String.length l - 5))))
           (String.split_on_char '\n' src))

let read path = In_channel.with_open_bin path In_channel.input_all

let cant_load st path e =
  only_looked := true;
  st.failed <- st.failed + 1;
  print_endline (Printf.sprintf "%s: can't load: %s" path (Option.get (failure e)))

(* Loads a source, then runs its examples and its tests. With [host], it sees that package, private names included. *)
let run_source (ctx : ctx) st ?host ?natives ~lookup path src =
  let w = ctx.w in
  let tests = is_test_file path in
  let rewrite = if tests then Some rewrite else None in
  match Loader.prepare ?host ?natives ?rewrite ctx ~path ~src ~lookup with
  | exception e when failure e <> None -> cant_load st path e
  | (_, m, _, layout) as prepared ->
    (try
       Loader.run_prepared ctx prepared;
       Runtime.flush_out w;
       run_examples ctx st path m src;
       if is_test_file path then run_tests ctx st path layout w.modules.(m).cells
     with e when failure e <> None ->
       only_looked := true;
       st.failed <- st.failed + 1;
       print_endline (Printf.sprintf "%s: failed: %s" path (Option.get (failure e))));
    Runtime.flush_out w

let run_file (ctx : ctx) st path =
  let w = ctx.w in
  let src = read path in
  if has_tests path src then begin
    ctx.b <- 0;
    w.root <- Package.root_of path;
    (* A file of std/ sees the natives of its package, small ones too, as when it loads. *)
    run_source ctx st ?natives:(Loader.std_natives w path) ~lookup:(Loader.lookup w) path src
  end

(* Which file of a package stopped, and on which line. *)
let place w dir = function
  | Pos.Load_error { file; pos; _ } -> Printf.sprintf "%s:%d" file (Pos.line pos)
  | Value.Kerr { at; _ } when at >= 0 && at < Vec.length w.sites ->
    let site = Vec.get w.sites at in
    Printf.sprintf "%s:%d" (fst (Vec.get w.files site.sfile)) (Pos.line site.spos)
  | _ -> Package.shown (Package.absolute dir)

(* A folder as a package: its files load together, the examples of each run with [examples], and each of [tests] sees them. *)
let run_folder (ctx : ctx) st ~examples dir tests =
  let w = ctx.w in
  let code = Package.files dir in
  if code = [] then List.iter (run_file ctx st) tests
  else if tests <> [] || (examples && List.exists (fun p -> has_tests p (read p)) code) then begin
    ctx.b <- 0;
    w.root <- Package.root_of dir;
    match Loader.folder ctx dir with
    | exception e when failure e <> None -> cant_load st (place w dir e) e
    | first ->
      Runtime.flush_out w;
      if examples then
        Array.iter
          (fun m ->
             let path = w.modules.(m).path in
             run_examples ctx st path m (read path))
          w.modules.(first).package;
      let lookup name =
        match Loader.in_package w first name with
        | Some b -> Some b
        | None -> Loader.lookup w name
      in
      List.iter (fun path -> run_source ctx st ~host:first ~lookup path (read path)) tests
  end

(* A folder is a package, as for use. In a tests folder and in std/ each file stands alone, and so does a file given by name,
   except a test, which needs its package. *)
(* What cesia test runs, each as a whole: the files that stand alone with something to run, and the folders of packages,
   each with its test files. A folder is a package, as for use; in a tests folder and in std/ each file stands alone, and so
   does a file given by name, except a test, which needs its package. *)
let units path =
  let whole = Package.is_dir path in
  let stands_alone p =
    in_tests_dir p || Filename.basename (Filename.dirname p) = "std" || not (whole || Package.is_test p)
  in
  let skip = Package.root_of path in
  let alone, packaged = List.partition stands_alone (source_files ~skip path) in
  List.map (fun p -> `File p) alone
  @ List.map
      (fun dir -> `Folder (dir, List.filter (fun p -> Package.is_test p && String.equal (Filename.dirname p) dir) packaged))
      (List.sort_uniq String.compare (List.map Filename.dirname packaged))

let run_unit ctx st ~examples = function
  | `File p -> run_file ctx st p
  | `Folder (dir, tests) -> run_folder ctx st ~examples dir tests

(* A worker runs one unit: a file, or a folder and the test files in it. *)
let worker_unit path =
  if Package.is_dir path then `Folder (path, List.filter Package.is_test (List.map (Filename.concat path) (Array.to_list (Sys.readdir path))))
  else `File path

(** The units of a path, as paths: one worker each. *)
let unit_paths path =
  List.filter_map
    (function
      | `File p -> if has_tests p (read p) then Some p else None
      | `Folder (dir, tests) -> if tests <> [] || List.exists (fun p -> has_tests p (read p)) (Package.files dir) then Some dir else None)
    (units path)

let run w (c : Testing.config) =
  let path = c.path and only = c.only and worker = c.worker in
  Props.st.cases <- c.cases;
  Props.st.update <- c.update;
  Props.st.dir <- c.dir;
  Props.st.timeout <- c.timeout;
  Props.st.clock <- c.clock;
  remove := c.remove;
  Loader.guarded w (fun ctx ->
      w.on_panic <- (fun _ _ -> ());
      Loader.init w;
      (* std/test and std/gen have their natives here. *)
      w.native_modules <- Props.natives @ w.native_modules;
      Props.st.active <- true;
      Props.st.on_case <- (fun () -> record.floor <- record.rank);
      w.on_checkpoint <- past;
      only_test := only;
      (* #note lives in module 0, beside #dict: only the rewritten verdicts name it. *)
      let core = w.modules.(0) in
      core.mnames <- core.mnames @ [ "#note", Array.length core.cells ];
      core.cells <- Array.append core.cells [| note |];
      core.stable <- Array.append core.stable [| true |];
      let st = { passed = 0; failed = 0 } in
      if worker then begin
        marked := true;
        run_unit ctx st ~examples:true (worker_unit path)
      end
      else List.iter (run_unit ctx st ~examples:(Package.is_dir path)) (units path);
      (match only with
       | Some name when not !only_looked ->
         st.failed <- st.failed + 1;
         print_endline (Messages.test_unknown path name [])
       | _ -> ());
      Runtime.flush_out w;
      if worker then print_endline (Printf.sprintf "\001= %d %d %b" st.passed st.failed Props.st.ran)
      else print_endline (Messages.test_summary st.passed st.failed (if Props.st.ran then Some (Rand.seed ()) else None));
      if not !kept && Props.st.dir <> "" && Sys.file_exists Props.st.dir then !remove Props.st.dir;
      if st.failed > 0 then 1 else 0)
