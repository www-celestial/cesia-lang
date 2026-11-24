open Types

(* Running code in a running program, the one engine of the prompt of cesia run --repl and of a debugger: at the file
   level of the main file's package, or in a frame of a stop, whose variables it reads. *)

let prompt_path = "<prompt>"

let get v name = Trie.find v (Trie.hash (Text name)) (Text name)

let use_line (alias, path) =
  if String.equal (Filename.basename path) alias then "use " ^ path ^ "\n" else "use " ^ path ^ " as " ^ alias ^ "\n"

let parsed path src = Parser.program ~file:path ~nesting:max_int (Lexer.tokens ~file:path ~nesting:max_int src)

(* The uses of a source, as aliases and paths; none when it doesn't parse, as its error comes later. *)
let uses_in path src =
  match parsed path src with
  | fn ->
    List.filter_map
      (fun (e : Ast.expr) -> match e.e with Use { upath; ualias } -> Some (ualias, upath) | _ -> None)
      (Array.to_list (Lazy.force fn.body))
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

(* The aliases that a dot follows in the code, as io in io.Print: the uses that a cell needs from the cells above. *)
let dotted code =
  match Lexer.tokens ~file:prompt_path ~nesting:Runtime.default_limits.nesting code with
  | exception Pos.Load_error _ -> []
  | toks ->
    let out = ref [] in
    let rec scan (toks : Lexer.token array) =
      Array.iteri
        (fun i (tk : Lexer.token) ->
           match tk.t with
           | NAME a when i + 1 < Array.length toks && toks.(i + 1).t = DOT -> out := a :: !out
           | TEXT parts -> List.iter (function Lexer.Code c -> scan c | Plain _ -> ()) parts
           | _ -> ())
        toks
    in
    scan toks;
    !out

(* Two definitions of a function are the same code when nothing tells them apart: the same name, the same path and the
   same text on the lines they span, so that an error in either prints the same; the same tree, node by node, at the same
   positions; each name bound to the same place, the same local or the same cell of the same module. A name of the cell
   that defines it is a cell of another module at each run of that cell: a function that reads one is never the same.
   Nothing whose meaning depends on the module that defines it, whose shapes and private names change at each run: no
   named struct, no private field, method or key read or written by name, no use, interface, inner named function or
   hook, and modules that see the same interfaces. *)
exception Differ

let same_code (w : world) (a : proto) (b : proto) =
  let last = ref 0 in
  let check c = if not c then raise Differ in
  let arr f x y = check (Array.length x = Array.length y); Array.iter2 f x y in
  let opt f x y = match x, y with None, None -> () | Some x, Some y -> f x y | _ -> raise Differ in
  let text x y = check (String.equal x y) in
  let public n = check (Lexer.is_public n) in
  let binding (x : Ast.binding) (y : Ast.binding) =
    match x, y with
    | Unresolved, Unresolved -> ()
    | Local i, Local j -> check (i = j)
    | Cell x, Cell y -> check (x.m = y.m && x.k = y.k && x.stable = y.stable)
    | _ -> raise Differ
  in
  let name (x : Ast.name) (y : Ast.name) = text x.text y.text; binding x.b y.b in
  let ptype (x : Ast.ptype) (y : Ast.ptype) =
    check (x.tpos = y.tpos && x.topt = y.topt && x.tbang = y.tbang);
    opt text x.tpkg y.tpkg;
    text x.tname y.tname;
    binding x.tb y.tb
  in
  let rec expr (x : Ast.expr) (y : Ast.expr) =
    check (x.id = y.id && x.pos = y.pos);
    last := max !last (Pos.line x.pos);
    match x.e, y.e with
    | Lint i, Lint j -> check (i = j)
    | Lfloat f, Lfloat g -> check (Int64.equal (Int64.bits_of_float f) (Int64.bits_of_float g))
    | Lbool p, Lbool q -> check (p = q)
    | Lmissing, Lmissing | Break, Break | End_index, End_index -> ()
    | Ltext p, Ltext q -> text p q
    | Interp p, Interp q -> arr part p q
    | Var p, Var q -> name p q
    | Bin (o, p1, p2), Bin (q, q1, q2) -> check (o = q); expr p1 q1; expr p2 q2
    | Neg p, Neg q | Not p, Not q | Question p, Question q -> expr p q
    | And (p1, p2), And (q1, q2) | Or (p1, p2), Or (q1, q2) | Range (p1, p2), Range (q1, q2) | In_op (p1, p2), In_op (q1, q2) ->
      expr p1 q1;
      expr p2 q2
    | Call p, Call q -> call p q
    | Assign (n, p), Assign (m, q) -> name n m; expr p q
    | If (c, p1, p2), If (d, q1, q2) -> expr c d; block p1 q1; block p2 q2
    | While p, While q -> check (p.has_break = q.has_break); expr p.cond q.cond; block p.body q.body
    | Return p, Return q -> check (p.tail = q.tail); opt expr p.rvalue q.rvalue
    | Lambda f, Lambda g -> func f g
    | Array_lit p, Array_lit q -> arr (arr expr) p q
    | Comp p, Comp q -> expr p.cbody q.cbody; name p.cvar q.cvar; expr p.csrc q.csrc; opt expr p.cguard q.cguard
    | Index (p, i, e), Index (q, j, f) -> check (e = f); expr p q; arr index i j
    | Field (p, n), Field (q, m) -> public n; text n m; expr p q
    | Struct_lit { sname = None; sfields = p }, Struct_lit { sname = None; sfields = q } ->
      arr (fun (n, x) (m, y) -> text n m; expr x y) p q
    | For p, For q -> check (p.f_break = q.f_break); name p.var q.var; expr p.iter q.iter; block p.fbody q.fbody
    | Set p, Set q -> name p.root q.root; arr step p.path q.path; expr p.value q.value
    | Destructure (p, x), Destructure (q, y) -> pat p q; expr x y
    | Match p, Match q -> expr p.subject q.subject; arr arm p.arms q.arms
    | _ -> raise Differ
  and block x y = arr expr x y
  and part (x : Ast.part) (y : Ast.part) = match x, y with Lit p, Lit q -> text p q | Hole p, Hole q -> expr p q | _ -> raise Differ
  and index (x : Ast.index) (y : Ast.index) = match x, y with All, All -> () | Ix p, Ix q -> expr p q | _ -> raise Differ
  and call (x : Ast.call) (y : Ast.call) =
    check (x.self_tail = y.self_tail);
    expr x.callee y.callee;
    arr (fun (p : Ast.arg) (q : Ast.arg) -> opt text p.aname q.aname; expr p.value q.value) x.args y.args
  and step (x : Ast.step) (y : Ast.step) =
    check (x.sp = y.sp);
    match x.sk, y.sk with
    | Sindex (i, e), Sindex (j, f) -> check (e = f); arr index i j
    | Sfield n, Sfield m -> public n; text n m
    | _ -> raise Differ
  and arm (x : Ast.arm) (y : Ast.arm) = pat x.pt y.pt; opt expr x.guard y.guard; expr x.abody y.abody
  and pat (x : Ast.pat) (y : Ast.pat) =
    match x, y with
    | Pname n, Pname m -> name n m
    | Pwild, Pwild -> ()
    | Plit p, Plit q -> expr p q
    | Parray p, Parray q -> arr pat p q
    | Pstruct p, Pstruct q -> arr (fun (n, x) (m, y) -> public n; text n m; pat x y) p q
    | _ -> raise Differ
  and func (f : Ast.func) (g : Ast.func) =
    let f = Cache.ready f and g = Cache.ready g in
    text f.fname g.fname;
    arr
      (fun (p : Ast.param) (q : Ast.param) -> text p.pname q.pname; opt expr p.default q.default; opt ptype p.ptype q.ptype)
      f.params g.params;
    opt ptype f.ret g.ret;
    check
      (f.nnodes = g.nnodes && f.fpos = g.fpos && f.nvars = g.nvars && f.var_names = g.var_names && f.captures = g.captures
       && f.maybe_undef = g.maybe_undef && f.has_return = g.has_return && f.has_self_tail = g.has_self_tail
       && f.kept = g.kept && f.cell_of = g.cell_of && f.export_of = g.export_of);
    last := max !last (Pos.line f.fpos);
    block (Lazy.force f.body) (Lazy.force g.body)
  in
  (* The text of lines [first] to [final] of a source, from 1: from the offset where line [first] starts to the one where
     line [final + 1] does, or the end. *)
  let lines src first final =
    let n = String.length src in
    let rec at i line l =
      if line >= l || i >= n then i else match String.index_from_opt src i '\n' with Some j -> at (j + 1) (line + 1) l | None -> n
    in
    let a = at 0 1 first in
    String.sub src a (at a first (final + 1) - a)
  in
  (* A method that a value finds through an interface is looked up from the module of the call, its uses and the
     interfaces of its package: the two modules see the same ones when they use the same packages and declare none. *)
  let ma = w.modules.(a.pm) and mb = w.modules.(b.pm) in
  let declares h = Hashtbl.fold (fun (host, _) _ found -> found || host = h) w.interfaces false in
  a.arity = b.arity && String.equal a.pname b.pname
  && ma.uses = mb.uses && (not (declares ma.host)) && not (declares mb.host)
  && (let pa, sa = Vec.get w.files a.file and pb, sb = Vec.get w.files b.file in
      String.equal pa pb
      && (match func a.func b.func with () -> true | exception Differ -> false)
      && (let first = Pos.line a.func.fpos in String.equal (lines sa first !last) (lines sb first !last)))

(* A function the code at the prompt defines again with the same code as the one before under its name takes the identity
   of that code: the JIT's native code, which tests a function by it, runs the new one at once, as it ran the old. The
   table keeps the last function of each name, at most [most_named] names; past them, it starts again, which only costs
   the next definition of each a compile. Not under a debugger, whose hooks are in the code. *)
let most_named = 1024

let twins (w : world) m (layout : Ast.layout) =
  if not w.hooks then begin
    let methods = List.map (fun (_, _, _, k) -> k) layout.methods in
    let table = w.debug.defined in
    Array.iter
      (fun (k, _) ->
         match w.modules.(m).cells.(k) with
         | Fun { proto; env = [||] } when not (List.mem k methods) ->
           let name = layout.cell_names.(k) in
           (match Hashtbl.find_opt table name with Some before when same_code w before proto -> proto.code <- before.code | _ -> ());
           if Hashtbl.length table >= most_named && not (Hashtbl.mem table name) then Hashtbl.reset table;
           Hashtbl.replace table name proto
         | _ -> ())
      layout.hoisted
  end

(* At the prompt: the code sees the main file's package, its uses and what was run at the prompt before. A cell of std/cells
   runs as the lines of its file from [line]: empty lines after the uses it needs put its own at their place, so that its
   errors and the calls that lead to them name the file and its lines. *)
let at_prompt ?cell ctx code =
  let w = ctx.w in
  let d = w.debug in
  (* A cell is no part of a program loaded: its file only names its modules, which the cells before it made. *)
  let target = if d.main = "" || cell <> None then -1 else Loader.module_of w d.main in
  let uses = uses_of w target @ d.typed_uses in
  let uses = match cell with Some _ -> (let used = dotted code in List.filter (fun (a, _) -> List.mem a used) uses) | None -> uses in
  let src, shift = source ~uses code in
  let path, src, shift =
    match cell with
    | Some (path, line) when line - 1 >= shift ->
      path, String.sub src 0 (String.length src - String.length code) ^ String.make (line - 1 - shift) '\n' ^ code, line - 1
    | Some (path, _) -> path, src, shift
    | None -> prompt_path, src, shift
  in
  let lookup name =
    match List.find_map (fun m -> Loader.in_module w m name) d.scope with
    | Some b -> Some b
    | None -> if target >= 0 then (match Loader.in_package w target name with Some b -> Some b | None -> Loader.lookup w name) else Loader.lookup w name
  in
  let typed = Lazy.from_val { code; shift; indent = 0 } in
  match Loader.prepare ctx ?host:(if target >= 0 then Some target else None) ~path ~src ~lookup with
  | exception e -> Value.err w (Text (error_text ctx ~typed e))
  | (file, m, _, layout) as prepared ->
    d.scope <- m :: d.scope;
    List.iter (fun (a, p) -> if not (List.mem_assoc a d.typed_uses) then d.typed_uses <- d.typed_uses @ [ a, p ]) (uses_in prompt_path code);
    if target >= 0 then replace_functions w ~target ~file layout else twins w m layout;
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

(* std/cells, in the session of a file: evalCell(code, line) runs a cell as the lines of the main file from that line, or
   code typed at a prompt for line 0;
   forgetNames(names) removes names from what the prompt sees, their values with them; valueOf(name) gives an Ok of the
   value of a name the prompt sees, or an Err. A cell is the program, not code run beside it: no debugger runs, and its
   long computations let the other fibers run, so that a stop reaches it. *)
let eval_cell ctx (a : t array) =
  let code = Native.text_arg ctx "evalCell" a.(0) in
  (* Line 0: code typed at a prompt beside the cells, which no line of the file holds. *)
  match a.(1) with
  | Int n when n >= 1 -> at_prompt ~cell:(ctx.w.debug.main, n) ctx code
  | _ -> at_prompt ~cell:(prompt_path, 1) ctx code

let names_arg ctx name v =
  match v with
  | Array { store = V items; rows; cols; _ } ->
    List.map (Native.text_arg ctx name) (Array.to_list (Array.sub items 0 (rows * cols)))
  | Array { rows; cols; _ } when rows * cols = 0 -> []
  | _ -> [ Native.text_arg ctx name v ]

let forget_names ctx (a : t array) =
  let w = ctx.w in
  let d = w.debug in
  let names = names_arg ctx "forgetNames" a.(0) in
  List.iter
    (fun m ->
       let md = w.modules.(m) in
       let gone, kept = List.partition (fun (n, _) -> List.mem n names) md.mnames in
       List.iter (fun (_, k) -> md.cells.(k) <- Undef) gone;
       md.mnames <- kept)
    d.scope;
  d.typed_uses <- List.filter (fun (alias, _) -> not (List.mem alias names)) d.typed_uses;
  Missing

let value_of ctx (a : t array) =
  let w = ctx.w in
  let name = Native.text_arg ctx "valueOf" a.(0) in
  match List.find_map (fun m -> Loader.in_module w m name) w.debug.scope with
  | Some (Ast.Cell { m; k; _ }) when w.modules.(m).cells.(k) != Undef -> Value.ok w w.modules.(m).cells.(k)
  | _ -> Value.err w (Text name)

(* setValue(name, x): an input of std/cells changed, its value x given to the name in place, in the cell of the module that
   holds it, so that the functions compiled with that cell read the new value: an Ok, or an Err when no module the prompt
   sees holds a value of the same kind under that name, a number for a number, a text for a text, true or false for
   true or false, or a struct of the same shape, as a date of std/date. A function's name, whose cell code may have
   folded, never changes here, nor a value of another kind, which code compiled with the name may not expect. *)
let set_value ctx (a : t array) =
  let w = ctx.w in
  let name = Native.text_arg ctx "setValue" a.(0) in
  let same old x =
    match old, x with
    | (Int _ | Float _), (Int _ | Float _) | Text _, Text _ | (True | False), (True | False) -> true
    | Struct { shape = s; _ }, Struct { shape = s'; _ } -> s.sid = s'.sid
    | _ -> false
  in
  match List.find_map (fun m -> Loader.in_module w m name) w.debug.scope with
  | Some (Ast.Cell { m; k; stable = false }) when same w.modules.(m).cells.(k) a.(1) ->
    w.modules.(m).cells.(k) <- a.(1);
    Value.ok w Missing
  | _ -> Value.err w (Text name)

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
    (match Lexer.tokens ~file:prompt_path ~nesting:ctx.w.limits.nesting code with
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
    "IsComplete", Native.nat ~params:[| "code" |] "IsComplete" 1 1 complete;
    "evalCell", Native.nat ~perm:Debug ~result:true "evalCell" 2 2 eval_cell;
    (* restartRandom(title): std/random starts again from the seed and a cell's title before the cell runs. *)
    "restartRandom", Native.nat ~perm:Debug "restartRandom" 1 1 (fun ctx a -> Rand.restart [ "cell"; Native.text_arg ctx "restartRandom" a.(0) ]; Missing);
    "forgetNames", Native.nat ~perm:Debug "forgetNames" 1 1 forget_names;
    "valueOf", Native.nat ~perm:Debug ~result:true "valueOf" 1 1 value_of;
    "setValue", Native.nat ~perm:Debug ~result:true "setValue" 2 2 set_value ]
