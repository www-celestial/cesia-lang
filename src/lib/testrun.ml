open Types

type stats = { mutable passed : int; mutable failed : int }

let rec source_files path =
  if Sys.is_directory path then begin
    let names = Sys.readdir path in
    Array.sort compare names;
    List.concat_map
      (fun n -> if n = "" || n.[0] = '.' || n = "_build" then [] else source_files (Filename.concat path n))
      (Array.to_list names)
  end
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
      | '"' -> Buffer.add_string b "\"\""
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
  Native { nname; perm = None; params = [||]; min_args = n; max_args = n; ret_ty = (fun _ -> TA); run; f1 = None; i2 = None }

let text_arg = function Text s -> s | _ -> ""
let int_arg = function Int i -> i | _ -> 0

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
      (try
         let got = Compile.call_back c a.(2) [||] in
         let want = Compile.call_back c a.(3) [||] in
         if Value.equal c got want then st.passed <- st.passed + 1
         else fail line code (Printf.sprintf "%s, got %s" (Value.show c want) (Value.show c got))
       with e ->
         match Loader.message_of_error e with
         | Some msg -> fail line code ("error: " ^ msg)
         | None -> raise e);
      Missing
    in
    let check_err c a =
      let line = int_arg a.(0) and code = text_arg a.(1) in
      (match Compile.call_back c a.(2) [||] with
       | v -> fail line code ("error, got " ^ Value.show c v)
       | exception Value.Kerr _ -> st.passed <- st.passed + 1);
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
       match Loader.message_of_error e with
       | Some msg ->
         st.failed <- st.failed + 1;
         print_endline (Printf.sprintf "%s:%d: the examples failed: %s" path (List.hd ex).line msg)
       | None -> raise e)

(* isGrows: is, then a capital. *)
let is_test_name name =
  String.length name > 2 && name.[0] = 'i' && name.[1] = 's' && name.[2] >= 'A' && name.[2] <= 'Z'

let run_tests (ctx : ctx) st path (layout : Ast.layout) cells =
  Array.iter
    (fun (k, (f : Ast.func)) ->
       if is_test_name f.fname && Array.length f.params = 0 && Lexer.split_method f.fname = None then begin
         let line = Pos.line f.fpos in
         ctx.b <- 0;
         ctx.site <- 0;
         match Compile.call_value ctx ~base:2 cells.(k) [||] with
         | True -> st.passed <- st.passed + 1
         | v ->
           st.failed <- st.failed + 1;
           print_endline (Printf.sprintf "%s:%d: %s returned %s" path line f.fname (Value.show ctx v))
         | exception e ->
           match Loader.message_of_error e with
           | Some msg ->
             st.failed <- st.failed + 1;
             print_endline (Printf.sprintf "%s:%d: %s failed: %s" path line f.fname msg)
           | None -> raise e
       end)
    layout.hoisted

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
  st.failed <- st.failed + 1;
  print_endline (Printf.sprintf "%s: can't load: %s" path (Option.get (Loader.message_of_error e)))

(* Loads a source, then runs its examples and its tests. With [host], it sees that package, private names included. *)
let run_source (ctx : ctx) st ?host ~lookup path src =
  let w = ctx.w in
  match Loader.prepare ?host ctx ~path ~src ~lookup with
  | exception e when Loader.message_of_error e <> None -> cant_load st path e
  | (_, m, _, layout) as prepared ->
    (try
       Loader.run_prepared ctx prepared;
       Runtime.flush_out w;
       run_examples ctx st path m src;
       if is_test_file path then run_tests ctx st path layout w.modules.(m).cells
     with e when Loader.message_of_error e <> None ->
       st.failed <- st.failed + 1;
       print_endline (Printf.sprintf "%s: failed: %s" path (Option.get (Loader.message_of_error e))));
    Runtime.flush_out w

let run_file (ctx : ctx) st path =
  let w = ctx.w in
  let src = read path in
  if has_tests path src then begin
    ctx.b <- 0;
    w.root <- Package.root_of path;
    (* The prelude sees the private natives, as when it loads. *)
    let is_prelude = Filename.basename path = "prelude" ^ Package.suffix && Filename.basename (Filename.dirname path) = "std" in
    run_source ctx st ~lookup:(if is_prelude then Loader.in_module w 0 else Loader.lookup w) path src
  end

(* Which file of a package stopped, and on which line. *)
let place w dir = function
  | Pos.Load_error { file; pos; _ } -> Printf.sprintf "%s:%d" file (Pos.line pos)
  | Value.Kerr { at; _ } when at >= 0 && at < Dynarray.length w.sites ->
    let site = Dynarray.get w.sites at in
    Printf.sprintf "%s:%d" (fst (Dynarray.get w.files site.sfile)) (Pos.line site.spos)
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
    | exception e when Loader.message_of_error e <> None -> cant_load st (place w dir e) e
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
let run_paths ctx st path =
  let whole = Package.is_dir path in
  let stands_alone p =
    in_tests_dir p || Filename.basename (Filename.dirname p) = "std" || not (whole || Package.is_test p)
  in
  let alone, packaged = List.partition stands_alone (source_files path) in
  List.iter (run_file ctx st) alone;
  List.iter
    (fun dir ->
       let tests = List.filter (fun p -> Package.is_test p && String.equal (Filename.dirname p) dir) packaged in
       run_folder ctx st ~examples:whole dir tests)
    (List.sort_uniq String.compare (List.map Filename.dirname packaged))

let run w ~path =
  Loader.guarded w (fun ctx ->
      w.on_panic <- (fun _ _ -> ());
      Loader.init w;
      let st = { passed = 0; failed = 0 } in
      run_paths ctx st path;
      Runtime.flush_out w;
      print_endline (Printf.sprintf "%d passed, %d failed" st.passed st.failed);
      if st.failed > 0 then 1 else 0)
