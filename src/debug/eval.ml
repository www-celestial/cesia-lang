open Types

(* Running code in a running program, the one engine of the prompt of cesia run --repl and of a debugger: at the file
   level of the main file's package, or in a frame of a stop, whose variables it reads. *)

let prompt_path = "<prompt>"

let get v name = Trie.find v (Trie.hash (Text name)) (Text name)

let use_line (alias, path) =
  if String.equal (Filename.basename path) alias then "use " ^ path ^ "\n" else "use " ^ path ^ " as " ^ alias ^ "\n"

let parsed path src = Parser.program ~file:path ~nesting:max_int (Lexer.tokens ~file:path src)

(* The uses of a source, as aliases and paths; none when it doesn't parse, as its error comes later. *)
let uses_in path src =
  match parsed path src with
  | fn ->
    List.filter_map
      (fun (e : Ast.expr) -> match e.e with Use { upath; ualias } -> Some (ualias, upath) | _ -> None)
      (Array.to_list fn.body)
  | exception Pos.Load_error _ -> []

(* The uses of the file of a module, as it was last loaded: the packages that code run there sees. *)
let uses_of w m =
  if m < 0 then []
  else
    let path = w.modules.(m).path in
    match Loader.source_of w path with Some src -> uses_in path src | None -> []

(* The code, after the uses of the place it runs in that it doesn't write itself: their lines come first, so that the
   value of the code is that of its last statement. Gives the source and the number of lines before the code. *)
let source ~uses code =
  let own = List.map fst (uses_in prompt_path code) in
  let extra = List.filter (fun (alias, _) -> not (List.mem alias own)) uses in
  let extra = List.fold_left (fun acc (a, p) -> if List.mem_assoc a acc then acc else acc @ [ a, p ]) [] extra in
  String.concat "" (List.map use_line extra) ^ code, List.length extra

(* The text of an error of the code: its line, counted in the code, when it has several. *)
let error_text w ~shift ~lines e =
  match Loader.message_of_error e with
  | None -> raise e
  | Some text ->
    let line =
      match e with
      | Pos.Load_error { pos; _ } -> Pos.line pos
      | Value.Kerr { at; _ } when at >= 0 && at < Dynarray.length w.sites ->
        let site = Dynarray.get w.sites at in
        if String.equal (fst (Dynarray.get w.files site.sfile)) prompt_path then Pos.line site.spos else 0
      | _ -> 0
    in
    if lines > 1 && line > shift then Printf.sprintf "line %d: %s" (line - shift) text else text

(* Runs a module made of the code above the frame of the native that runs it, as a call would: errors and traces see
   a frame there, and the caller's stays as it was. Gives the value of the last statement. *)
let run_above ctx (file, m, fn, _) =
  let b = ctx.b and s = ctx.site in
  let above = match (Dynarray.get ctx.w.sites s).sver with Some v -> Int.max v.size (v.frame + 2) | None -> 2 in
  let nb = b + above in
  if nb + 2 > ctx.cap then Runtime.grow ctx (nb + 2);
  ctx.i.(nb) <- b;
  ctx.i.(nb + 1) <- s;
  ctx.b <- nb;
  Fun.protect
    ~finally:(fun () ->
        ctx.b <- b;
        ctx.site <- s)
    (fun () -> Compile.run_main ctx ~file ~m fn)

(* Code run at a stop or at the prompt is no part of the program: it never stops on its own errors or breakpoints. *)
let quietly ctx f =
  let d = ctx.w.debug in
  let before = d.stopped in
  d.stopped <- true;
  Fun.protect ~finally:(fun () -> d.stopped <- before) f

(* A function of the program that the code at the prompt defines again: it takes the new definition, as a reload
   gives it, and the program goes on with it. *)
let replace_functions w ~target ~file (layout : Ast.layout) =
  let replaced =
    Array.fold_left
      (fun n (k, f) ->
         match Loader.in_package w target layout.cell_names.(k) with
         | Some (Ast.Cell { m; k = tk; _ }) ->
           (match w.modules.(m).cells.(tk) with
            | Fun { proto; env = [||] } ->
              Compile.replace proto ~file f;
              n + 1
            | _ -> n)
         | _ -> n)
      0 layout.hoisted
  in
  if replaced > 0 then begin
    w.reloads <- w.reloads + 1;
    Compile.retire_all w
  end

let lines_of code = List.length (String.split_on_char '\n' (String.trim code))

(* At the prompt: the code sees the main file's package, its uses and what was run at the prompt before. *)
let at_prompt ctx code =
  let w = ctx.w in
  let d = w.debug in
  let target = if d.main = "" then -1 else Loader.module_of w d.main in
  let src, shift = source ~uses:(uses_of w target @ d.typed_uses) code in
  let lookup name =
    match List.find_map (fun m -> Loader.in_module w m name) d.scope with
    | Some b -> Some b
    | None -> if target >= 0 then (match Loader.in_package w target name with Some b -> Some b | None -> Loader.lookup w name) else Loader.lookup w name
  in
  let lines = lines_of code in
  match Loader.prepare ctx ?host:(if target >= 0 then Some target else None) ~path:prompt_path ~src ~lookup with
  | exception e -> Value.err w (Text (error_text w ~shift ~lines e))
  | (file, m, _, layout) as prepared ->
    d.scope <- m :: d.scope;
    List.iter (fun (a, p) -> if not (List.mem_assoc a d.typed_uses) then d.typed_uses <- d.typed_uses @ [ a, p ]) (uses_in prompt_path code);
    if target >= 0 then replace_functions w ~target ~file layout;
    match run_above ctx prepared with
    | v -> Value.ok w v
    | exception e -> Value.err w (Text (error_text w ~shift ~lines e))

(* The names and values of the variables of a frame of a stop. *)
let frame_vars frame =
  match get frame "Vars" with
  | Array { store = V vars; rows; cols; _ } ->
    List.filter_map
      (fun v -> match get v "Name", get v "Value" with Text n, x when x != Undef -> Some (n, x) | _ -> None)
      (Array.to_list (Array.sub vars 0 (rows * cols)))
  | _ -> []

(* The code as a function of the frame's variables, made once for a frame's names and kept, so that a condition tested at
   each pass costs a call. *)
let as_function ctx ~path ~names code =
  let w = ctx.w in
  let target = Loader.module_of w path in
  let key = String.concat "\000" (string_of_int target :: code :: names) in
  match Hashtbl.find_opt w.debug.made key with
  | Some g -> g
  | None ->
    let src, _ =
      source ~uses:(uses_of w target) ("(" ^ String.concat ", " names ^ ") -> (" ^ String.trim code ^ ")")
    in
    let lookup name = if target >= 0 then match Loader.in_package w target name with Some b -> Some b | None -> Loader.lookup w name else Loader.lookup w name in
    let g = run_above ctx (Loader.prepare ctx ?host:(if target >= 0 then Some target else None) ~path:prompt_path ~src ~lookup) in
    Hashtbl.replace w.debug.made key g;
    g

(* In a frame: an expression of its variables, of its package and of the packages its file uses. *)
let in_frame ctx code frame =
  let w = ctx.w in
  let path = match get frame "File" with Text p -> p | v -> Runtime.fail ctx Type (Messages.need_frame (Value.describe v)) in
  let vars = frame_vars frame in
  match
    let g = as_function ctx ~path ~names:(List.map fst vars) code in
    Compile.call_back ctx g (Array.of_list (List.map snd vars))
  with
  | v -> Value.ok w v
  | exception e -> Value.err w (Text (error_text w ~shift:0 ~lines:1 e))

let eval ctx (a : t array) =
  let code = Native.text_arg ctx "Eval" a.(0) in
  quietly ctx (fun () ->
      match if Array.length a > 1 then a.(1) else Missing with
      | Missing -> at_prompt ctx code
      | frame -> in_frame ctx code frame)

(* A condition of a breakpoint, at a site, with the variables there: an error stops too, to be seen. *)
let test ctx s cond =
  match quietly ctx (fun () -> in_frame ctx cond (Debug.frame ctx ctx.b s)) with
  | Struct { shape = { sname = Some "Ok"; _ }; fields = [| v |]; _ } -> v <> False && v <> Missing
  | _ -> true

let read_file path = try Some (In_channel.with_open_bin path In_channel.input_all) with Sys_error _ -> None

(* The files whose text changed since they were loaded reload, as cesia run --watch does: Ok with their paths, or Err with
   the errors, and the code of those stays as it was. *)
let reload ctx _ =
  let w = ctx.w in
  let changed =
    List.filter
      (fun path ->
         match Loader.source_of w path, read_file path with
         | Some before, Some now -> not (String.equal before now)
         | _ -> false)
      (List.sort_uniq compare (Loader.watched w))
  in
  match Loader.reload_all w changed with
  | [] -> Value.ok w (Debug.row (List.map (fun p -> Text p) changed))
  | failed -> Value.err w (Text (String.concat "" (List.sort_uniq compare (List.map snd failed))))

(* Is the code whole, or does it stop in the middle of a block, of a list or of an expression: the prompt then reads
   another line. *)
let complete ctx (a : t array) =
  let code = Native.text_arg ctx "Complete" a.(0) in
  Value.of_bool
    (match Lexer.tokens ~file:prompt_path code with
     | exception Pos.Load_error _ -> true
     | toks ->
       let fin = toks.(Array.length toks - 1).pos in
       match Parser.program ~file:prompt_path ~nesting:max_int toks with
       | _ -> true
       | exception Pos.Load_error { pos; _ } ->
         Pos.line pos < Pos.line fin || (Pos.line pos = Pos.line fin && Pos.col pos < Pos.col fin))

(* The binary holds these names and the permission each needs: see src/sys/sys_modules.ml. *)
let natives =
  [ "Eval", Native.nat ~perm:Debug ~params:[| "code"; "frame" |] "Eval" 1 2 eval;
    "Reload", Native.nat ~perm:Debug "Reload" 0 0 reload;
    "Complete", Native.nat ~params:[| "code" |] "Complete" 1 1 complete ]
