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

(* An error of the code, as text, in the one form of every error of Cesia: its place, then its message. In the code
   typed, the place is <prompt> with the line and the column in that code, and the line of code with a ^ follows; elsewhere,
   in a function of the program, it is as the program shows it, with its line of code and the calls that led there. Made
   before the frames are left. *)
exception Failed of string

(* The code typed, in the source that runs it: the lines of uses before it, and on its first line the columns of what
   wraps it. *)
type typed = { code : string; shift : int; indent : int }

let contains s part =
  let n = String.length part and m = String.length s in
  let rec at i = i + n <= m && (String.sub s i n = part || at (i + 1)) in
  at 0

let error_text ?above ctx ~(typed : typed Lazy.t) e =
  let w = ctx.w in
  let in_typed at = String.equal (fst (Vec.get w.files (Vec.get w.sites at).sfile)) prompt_path in
  let place =
    match e with
    | Pos.Load_error { file; pos; hint; _ } when String.equal file prompt_path -> Some (pos, hint)
    | Value.Kerr { at; hint; _ } when at >= 0 && at < Vec.length w.sites && in_typed (Runtime.user_site ctx at) ->
      Some ((Vec.get w.sites (Runtime.user_site ctx at)).spos, hint)
    | _ -> None
  in
  match e, place with
  | Failed text, _ -> text
  | _, Some (pos, hint) ->
    let text = Option.value (Loader.message_of_error e) ~default:"" in
    let t = Lazy.force typed in
    let line = Pos.line pos - t.shift in
    if line < 1 then text
    else
      let col = if line = 1 then Int.max 1 (Pos.col pos - t.indent) else Pos.col pos in
      String.trim
        (Loader.format_error ~source:(Some t.code) ~path:prompt_path ~pos:(Pos.make line col) ~text ~hint ~trace:[])
  | _, None -> (
    (* The call from the code typed is no line of the program. *)
    let ours l = contains l ("(" ^ prompt_path ^ ":") in
    match Loader.error_report ?above ctx e with
    | Some text -> String.trim (String.concat "\n" (List.filter (fun l -> not (ours l)) (String.split_on_char '\n' text)))
    | None -> raise e)

(* Runs f, which makes a frame at base [above], the frame base and the site given back after it, and an error made into its
   text first, with the frames above that one as they were when it was raised. *)
let framed ctx ~above ~typed f =
  let b = ctx.b and s = ctx.site in
  match f () with
  | v ->
    ctx.b <- b;
    ctx.site <- s;
    v
  | exception e ->
    let text = error_text ~above ctx ~typed e in
    ctx.b <- b;
    ctx.site <- s;
    raise (Failed text)

(* Where a call from the native that runs at the current site puts its frame, as [Compile.call_back] does. *)
let call_base ctx = match (Vec.get ctx.w.sites ctx.site).sver with Some v -> v.size | None -> 0

(* Runs a module made of the code above the frame of the native that runs it, as a call would: errors and traces see
   a frame there, and the caller's stays as it was. Gives the value of the last statement. *)
let run_above ctx ~typed (file, m, fn, _) =
  let b = ctx.b and s = ctx.site in
  let nb = b + Int.max (call_base ctx) 2 in
  framed ctx ~above:nb ~typed (fun () ->
      if nb + 2 > ctx.cap then Runtime.grow ctx (nb + 2);
      ctx.i.(nb) <- b;
      ctx.i.(nb + 1) <- s;
      ctx.b <- nb;
      Compile.run_main ctx ~file ~m fn)

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
  let typed = Lazy.from_val { code; shift; indent = 0 } in
  match Loader.prepare ctx ?host:(if target >= 0 then Some target else None) ~path:prompt_path ~src ~lookup with
  | exception e -> Value.err w (Text (error_text ctx ~typed e))
  | (file, m, _, layout) as prepared ->
    d.scope <- m :: d.scope;
    List.iter (fun (a, p) -> if not (List.mem_assoc a d.typed_uses) then d.typed_uses <- d.typed_uses @ [ a, p ]) (uses_in prompt_path code);
    if target >= 0 then replace_functions w ~target ~file layout;
    match run_above ctx ~typed prepared with
    | v -> Value.ok w v
    | exception Failed text -> Value.err w (Text text)

(* The names and values of the variables of a frame of a stop. *)
let frame_vars frame =
  match get frame "Vars" with
  | Array { store = V vars; rows; cols; _ } ->
    List.filter_map
      (fun v -> match get v "Name", get v "Value" with Text n, x when x != Undef -> Some (n, x) | _ -> None)
      (Array.to_list (Array.sub vars 0 (rows * cols)))
  | _ -> []

(* The code as a function of the frame's variables, the source that makes it, and where the code typed is in that source. *)
let wrapped w ~target ~names code =
  let head = "(" ^ String.concat ", " names ^ ") -> (" and body = String.trim code in
  let src, shift = source ~uses:(uses_of w target) (head ^ body ^ ")") in
  src, { code = body; shift; indent = String.length head }

(* The code as a function of the frame's variables, made once for a frame's names and kept, so that a condition tested at
   each pass costs a call. *)
let as_function ctx ~path ~names code =
  let w = ctx.w in
  let target = Loader.module_of w path in
  let key = String.concat "\000" (string_of_int target :: code :: names) in
  match Hashtbl.find_opt w.debug.made key with
  | Some g -> g
  | None ->
    (* The code alone first: its own syntax error shows as it was typed, not in the function made around it. *)
    let body = String.trim code in
    (match parsed prompt_path body with
     | exception (Pos.Load_error _ as e) ->
       raise (Failed (error_text ctx ~typed:(Lazy.from_val { code = body; shift = 0; indent = 0 }) e))
     | _ -> ());
    let src, t = wrapped w ~target ~names code in
    let lookup name = if target >= 0 then match Loader.in_package w target name with Some b -> Some b | None -> Loader.lookup w name else Loader.lookup w name in
    let g = run_above ctx ~typed:(Lazy.from_val t) (Loader.prepare ctx ?host:(if target >= 0 then Some target else None) ~path:prompt_path ~src ~lookup) in
    Hashtbl.replace w.debug.made key g;
    g

(* In a frame: an expression of its variables, of its package and of the packages its file uses. *)
let in_frame ctx code frame =
  let w = ctx.w in
  let path = match get frame "File" with Text p -> p | _ -> Runtime.fail ctx Type (Messages.need_frame (Value.describe frame)) in
  let vars = frame_vars frame in
  match
    framed ctx ~above:(ctx.b + call_base ctx)
      ~typed:(lazy (snd (wrapped w ~target:(Loader.module_of w path) ~names:(List.map fst vars) code)))
      (fun () ->
        let g = as_function ctx ~path ~names:(List.map fst vars) code in
        Compile.call_back ctx g (Array.of_list (List.map snd vars)))
  with
  | v -> Value.ok w v
  | exception Failed text -> Value.err w (Text text)

let eval ctx (a : t array) =
  let code = Native.text_arg ctx "Eval" a.(0) in
  quietly ctx (fun () ->
      match if Array.length a > 1 then a.(1) else Missing with
      | Missing -> at_prompt ctx code
      | frame -> in_frame ctx code frame)

(* A condition of a breakpoint, at a site, with the variables there: whether it holds, or the error it gives. *)
let test ctx s cond =
  (* The code runs above the frame of the site: the hook doesn't set it. *)
  let before = ctx.site in
  ctx.site <- s;
  match Fun.protect ~finally:(fun () -> ctx.site <- before) (fun () -> quietly ctx (fun () -> in_frame ctx cond (Debug.frame ctx ctx.b s))) with
  | Struct { shape = { sname = Some "Ok"; _ }; fields = V [| v |]; _ } -> Ok (v <> False && v <> Missing)
  | Struct { fields = V [| Text text |]; _ } -> Error text
  | v -> Error (Value.describe v)

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
  let code = Native.text_arg ctx "IsComplete" a.(0) in
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
  [ "Eval", Native.nat ~perm:Debug ~params:[| "code"; "frame" |] ~result:true "Eval" 1 2 eval;
    "Reload", Native.nat ~perm:Debug ~result:true "Reload" 0 0 reload;
    "IsComplete", Native.nat ~params:[| "code" |] "IsComplete" 1 1 complete ]
