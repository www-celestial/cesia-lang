open Types

type stats = { mutable passed : int; mutable failed : int }

let rec kp_files path =
  if Sys.is_directory path then begin
    let names = Sys.readdir path in
    Array.sort compare names;
    List.concat_map
      (fun n -> if n = "" || n.[0] = '.' || n = "_build" then [] else kp_files (Filename.concat path n))
      (Array.to_list names)
  end
  else if Filename.check_suffix path ".kp" then [ path ]
  else []

let in_tests_dir path = List.mem "tests" (String.split_on_char '/' (Filename.dirname path))
let is_test_file path = Filename.check_suffix path "_test.kp" || in_tests_dir path

(* A comment line: the text after --. *)
let comment_text line =
  let t = String.trim line in
  if String.starts_with ~prefix:"--" t then Some (String.sub t 2 (String.length t - 2)) else None

let is_name_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c >= '\128'

(* A top-level definition: defn, struct or name(...) = ... *)
let is_definition line =
  String.starts_with ~prefix:"defn " line
  || String.starts_with ~prefix:"struct " line
  || begin
    let n = String.length line and i = ref 0 in
    while !i < n && is_name_char line.[!i] do incr i done;
    !i > 0 && !i < n && line.[!i] = '('
  end

type example = { line : int; code : string; want : [ `Stmt | `Value of string | `Error ] }

let find_sub s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = if i + m > n then None else if String.sub s i m = sub then Some i else go (i + 1) in
  go 0

(* The examples: the indented lines of a comment placed just above a definition. *)
let examples src =
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let out = ref [] and block = ref [] in
  Array.iteri
    (fun i line ->
       match comment_text line with
       | Some text when String.length line > 0 && line.[0] = '-' -> block := (i + 1, text) :: !block
       | _ ->
         if is_definition line then
           List.iter
             (fun (n, text) ->
                if String.starts_with ~prefix:"  " text then begin
                  let text = String.trim text in
                  let example =
                    match find_sub text "-->" with
                    | None -> { line = n; code = text; want = `Stmt }
                    | Some k ->
                      let code = String.trim (String.sub text 0 k) in
                      let r = String.trim (String.sub text (k + 3) (String.length text - k - 3)) in
                      { line = n; code; want = (if r = "error" then `Error else `Value r) }
                  in
                  out := example :: !out
                end)
             (List.rev !block);
         block := [])
    lines;
  List.rev !out

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

let example_source ex =
  let b = Buffer.create 256 in
  List.iter
    (fun e ->
       Buffer.add_string b
         (match e.want with
          | `Stmt -> e.code
          | `Value r -> Printf.sprintf "_doc_eq(%d, %s, () -> (%s), () -> (%s))" e.line (quote e.code) e.code r
          | `Error -> Printf.sprintf "_doc_err(%d, %s, () -> (%s))" e.line (quote e.code) e.code);
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
    let doc_eq = native "_doc_eq" 4 check_eq and doc_err = native "_doc_err" 3 check_err in
    let doc_m = Array.length w.modules in
    let helpers =
      { mname = "doc"; path = ""; cells = [| doc_eq; doc_err |]; mnames = [ "_doc_eq", 0; "_doc_err", 1 ];
        stable = [| true; true |] }
    in
    w.modules <- Array.append w.modules [| helpers |];
    let lookup name =
      match Loader.in_module w doc_m name with
      | Some b -> Some b
      | None ->
        match Loader.in_module w m name with
        | Some b -> Some b
        | None -> Loader.lookup w name
    in
    (try
       let prepared = Loader.prepare ctx ~path:(path ^ " (examples)") ~src:(example_source ex) ~lookup in
       ctx.b <- 0;
       Loader.run_prepared ctx prepared
     with e ->
       match Loader.message_of_error e with
       | Some msg ->
         st.failed <- st.failed + 1;
         print_endline (Printf.sprintf "%s:%d: the examples failed: %s" path (List.hd ex).line msg)
       | None -> raise e)

let run_tests (ctx : ctx) st path (layout : Ast.layout) cells =
  Array.iter
    (fun (k, (f : Ast.func)) ->
       if String.starts_with ~prefix:"is_" f.fname && Array.length f.params = 0 then begin
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
              (String.starts_with ~prefix:"is_" l || String.starts_with ~prefix:"defn is_" l))
           (String.split_on_char '\n' src))

let run_file (ctx : ctx) st path =
  let w = ctx.w in
  let src = In_channel.with_open_bin path In_channel.input_all in
  if has_tests path src then begin
    ctx.b <- 0;
    w.entry_dir <- Filename.dirname path;
    (* std/ sees the private natives, as when loading the prelude. *)
    let in_std = Filename.basename (Filename.dirname path) = "std" in
    let lookup = if in_std then Loader.in_module w 0 else Loader.lookup w in
    match Loader.prepare ctx ~path ~src ~lookup with
    | exception e when Loader.message_of_error e <> None ->
      st.failed <- st.failed + 1;
      print_endline (Printf.sprintf "%s: can't load: %s" path (Option.get (Loader.message_of_error e)))
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
  end

let run w ~path =
  Loader.guarded w (fun ctx ->
      w.on_panic <- (fun _ _ -> ());
      Loader.init w;
      let st = { passed = 0; failed = 0 } in
      List.iter (run_file ctx st) (kp_files path);
      Runtime.flush_out w;
      print_endline (Printf.sprintf "%d passed, %d failed" st.passed st.failed);
      if st.failed > 0 then 1 else 0)
