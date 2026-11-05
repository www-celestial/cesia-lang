open Lexer
open Ast

(* Lines: a newline ends a statement. Ignore: inside () and {}. Row: inside [ ], it separates rows. *)
type mode = Lines | Ignore | Row

type p = {
  toks : token array;
  file : string;
  nesting : int;
  hooks : bool;  (* a hook before each statement *)
  mutable i : int;
  mutable depth : int;
  mutable mode : mode;
  mutable next_id : int;
  mutable loop : bool ref option;  (* the current loop, and whether it contains a break *)
  mutable in_function : bool;
  mutable in_index : int;  (* > 0: [end] means the end of the indexed array *)
  mutable saw_end : bool;
  mutable stmt_at : int;  (* where the current statement starts *)
}

let error p pos (m : Messages.t) =
  raise (Pos.Load_error { file = p.file; pos; kind = "syntax"; text = m.text; hint = m.hint })

let cur p =
  if p.mode = Ignore then
    while p.toks.(p.i).t = NL do p.i <- p.i + 1 done;
  p.toks.(p.i)

let advance p = p.i <- p.i + 1

let skip_nl p =
  while p.toks.(p.i).t = NL do p.i <- p.i + 1 done

let tok_text = function
  | INT i -> string_of_int i
  | FLOAT x -> Value.float_text x
  | TEXT _ -> "a text"
  | NAME n -> "\"" ^ n ^ "\""
  | NL -> "the end of the line"
  | EOF -> "the end of the file"
  | IF -> "if" | ELSE -> "else" | END -> "end" | FOR -> "for" | IN -> "in" | WHILE -> "while"
  | BREAK -> "break" | RETURN -> "return" | DEFN -> "defn" | MATCH -> "match" | STRUCT -> "struct" | INTERFACE -> "interface"
  | AND -> "and" | OR -> "or" | NOT -> "not" | THEN -> "then" | USE -> "use" | TRUE -> "true"
  | FALSE -> "false" | MISSING -> "missing" | PLUS -> "+" | MINUS -> "-" | STAR -> "*" | SLASH -> "/"
  | CARET -> "^" | ASSIGN -> "=" | EQEQ -> "==" | NE -> "!=" | LT -> "<" | LE -> "<=" | GT -> ">" | GE -> ">="
  | PLUSEQ -> "+=" | MINUSEQ -> "-=" | STAREQ -> "*=" | SLASHEQ -> "/=" | ARROW -> "->" | COLON -> ":"
  | SEMI -> ";" | COMMA -> "," | DOT -> "." | QUESTION -> "?" | LP -> "(" | RP -> ")" | LB -> "[" | RB -> "]" | LC -> "{" | RC -> "}"

let unexpected p what =
  let t = cur p in
  error p t.pos (Messages.expected what (tok_text t.t))

let expect p tok what =
  if (cur p).t = tok then advance p else unexpected p what

let node p pos e =
  let id = p.next_id in
  p.next_id <- id + 1;
  { id; pos; e }

let with_mode p mode f =
  let saved = p.mode in
  p.mode <- mode;
  let r = f () in
  p.mode <- saved;
  r

let deeper p f =
  p.depth <- p.depth + 1;
  if p.depth > p.nesting then error p (cur p).pos Messages.too_nested;
  let r = f () in
  p.depth <- p.depth - 1;
  r

let name text = { text; b = Unresolved }

let hook p pos = node p pos (Hook { live = Bytes.empty })

(* The body of a short form: a single statement. *)
let hooked p pos (e : expr) = if p.hooks then [| hook p pos; e |] else [| e |]

(* Where the token after the [)] matching the current [(] is. *)
let paren_end p =
  let k = ref (p.i + 1) and depth = ref 1 in
  while !depth > 0 && p.toks.(!k).t <> EOF do
    (match p.toks.(!k).t with
     | LP -> incr depth
     | RP -> decr depth
     | _ -> ());
    incr k
  done;
  if p.mode = Ignore then
    while p.toks.(!k).t = NL do incr k done;
  !k

let after_paren p = p.toks.(paren_end p).t

(* (r Rect) Area(, the current token being the parenthesis: no expression has two names in a row. A typed parameter has
   them too, in (s Shape) -> or defn (s Shape), but no name and parenthesis after it, except in the body of a defn on one
   line, which [function_expr] tells apart. *)
let is_receiver p =
  (match p.toks.(p.i + 1).t, p.toks.(p.i + 2).t with NAME _, NAME _ -> true | _ -> false)
  &&
  let k = paren_end p in
  (match p.toks.(k).t with NAME _ -> true | _ -> false) && p.toks.(k + 1).t = LP

(* Where a type written at token k ends, Point or geo.Point, either with ?: k itself if there is none. *)
let type_end p k =
  let opt j = if p.toks.(j).t = QUESTION then j + 1 else j in
  match p.toks.(k).t with
  | NAME _ when p.toks.(k + 1).t = DOT -> (match p.toks.(k + 2).t with NAME _ -> opt (k + 3) | _ -> k)
  | NAME _ -> opt (k + 1)
  | _ -> k

(* At token k, the end of the line of a defn header, after its return type if it has one. *)
let ends_header p k = match p.toks.(type_end p k).t with NL | EOF -> true | _ -> false

let next_tok p =
  let k = ref (p.i + 1) in
  if p.mode = Ignore then
    while p.toks.(!k).t = NL do incr k done;
  p.toks.(!k).t

let rec expr p =
  deeper p (fun () ->
      let t = cur p in
      match t.t with
      | NAME _ when next_tok p = ARROW -> lambda p
      | LP when after_paren p = ARROW -> lambda p
      | _ -> then_expr p)

(* x then f(a): the value becomes the last positional argument, or takes the place of a lone [it]. *)
and then_expr p =
  let l = ref (or_expr p) in
  let rec go () =
    if p.mode = Lines && (cur p).t = NL && following p = THEN then skip_nl p;
    let t = cur p in
    if t.t = THEN then begin
      advance p;
      skip_nl p;
      let rhs = or_expr p in
      l := apply_then p t.pos !l rhs;
      go ()
    end
  in
  go ();
  !l

(* The first token after the newlines. *)
and following p =
  let k = ref p.i in
  while p.toks.(!k).t = NL do incr k done;
  p.toks.(!k).t

and apply_then p pos value (rhs : expr) =
  let arg v = { aname = None; value = v } in
  match rhs.e with
  | Call call when not (mentions_it call.callee) ->
    let is_it (a : arg) = is_it_alone a.value in
    if Array.exists is_it call.args then begin
      let args = Array.map (fun a -> if is_it a then { a with value } else a) call.args in
      node p pos (Call { call with args })
    end else begin
      let positional, named = List.partition (fun a -> a.aname = None) (Array.to_list call.args) in
      node p pos (Call { call with args = Array.of_list (positional @ [ arg value ] @ named) })
    end
  | _ ->
    let callee = if mentions_it rhs then short_function p rhs else rhs in
    node p pos (Call { callee; args = [| arg value |]; self_tail = false })

and is_it_alone (e : expr) =
  match e.e with
  | Var { text = "it"; _ } -> true
  | _ -> false

(* Without entering nested functions. *)
and mentions_it (e : expr) =
  is_it_alone e
  || begin
    let found = ref false in
    Resolve.children (fun x -> if mentions_it x then found := true) e;
    !found
  end

(* it -> body. The body was parsed in the enclosing function: its ids stay unique there. *)
and short_function p (body : expr) =
  let returned = node p body.pos (Return { rvalue = Some body; tail = true }) in
  let f =
    { fname = "<anonymous>"; params = [| { pname = "it"; default = None; ptype = None } |]; body = [| returned |];
      ret = None; nnodes = p.next_id; fpos = body.pos; nvars = 0; var_names = [||]; captures = [||]; maybe_undef = [||];
      has_return = false; has_self_tail = false; kept = 0; cell_of = [||]; export_of = [||] }
  in
  node p body.pos (Lambda f)

(* An argument mentioning [it] without being a lone [it] becomes the function it -> argument. *)
and it_sugar p (args : arg array) =
  Array.map
    (fun (a : arg) ->
       if (not (is_it_alone a.value)) && mentions_it a.value then { a with value = short_function p a.value } else a)
    args

(* The body of a function: its node ids restart from zero. *)
and in_func p fname fpos parse =
  let saved_id = p.next_id and saved_loop = p.loop and saved_fn = p.in_function in
  p.next_id <- 0;
  p.loop <- None;
  p.in_function <- true;
  let params, ret, body = parse () in
  let nnodes = p.next_id in
  p.next_id <- saved_id;
  p.loop <- saved_loop;
  p.in_function <- saved_fn;
  { fname; params; ret; body; nnodes; fpos; nvars = 0; var_names = [||]; captures = [||]; maybe_undef = [||];
    has_return = false; has_self_tail = false; kept = 0; cell_of = [||]; export_of = [||] }

(* NAME [TYPE] [= default]: a parameter, or a field of a struct in either form. *)
and param p what =
  match (cur p).t with
  | NAME pname ->
    advance p;
    let ptype = match (cur p).t with NAME _ -> Some (type_ref p) | _ -> None in
    let default =
      if (cur p).t = ASSIGN then begin
        advance p;
        Some (expr p)
      end else None
    in
    { pname; default; ptype }
  | _ -> unexpected p what

(* Point, geo.Point, and ? when it also takes missing. *)
and type_ref p =
  let tpos = (cur p).pos in
  let word () = match (cur p).t with NAME n -> advance p; n | _ -> unexpected p "a type" in
  let first = word () in
  let tpkg, tname = if (cur p).t = DOT then (advance p; Some first, word ()) else None, first in
  let topt = (cur p).t = QUESTION in
  if topt then advance p;
  { tpos; tpkg; tname; topt; tb = Unresolved }

(* (params) or { fields }. *)
and listed p opening close what =
  with_mode p Ignore (fun () ->
      expect p opening (Printf.sprintf "\"%s\"" (tok_text opening));
      let out = ref [] in
      while (cur p).t <> close do
        out := param p what :: !out;
        if (cur p).t = COMMA then advance p
        else if (cur p).t <> close then unexpected p (Printf.sprintf "\",\" or \"%s\"" (tok_text close))
      done;
      advance p;
      Array.of_list (List.rev !out))

and params p = listed p LP RP "a parameter name"

and lambda p =
  let pos = (cur p).pos in
  let f =
    in_func p "<anonymous>" pos (fun () ->
        let ps =
          match (cur p).t with
          | NAME pname -> advance p; [| { pname; default = None; ptype = None } |]
          | _ -> params p
        in
        Array.iter (fun q -> Option.iter (fun t -> error p t.tpos Messages.lambda_type) q.ptype) ps;
        let arrow = cur p in
        expect p ARROW "\"->\"";
        skip_nl p;
        let body = expr p in
        ps, None, hooked p body.pos (node p arrow.pos (Return { rvalue = Some body; tail = true })))
  in
  node p pos (Lambda f)

(* defn name(params) body end, defn (r Rect) name(params) body end, or defn (params) body end, after the keyword. *)
and function_expr p pos =
  with_mode p Lines (fun () ->
      (* A method starts a statement, and its parameters end their line, or its return type does: defn (p Pt) Text(p.X) end
         is a function. *)
      let method_line () =
        let saved = p.i in
        p.i <- paren_end p + 1;
        let k = paren_end p in
        p.i <- saved;
        ends_header p k
      in
      let named =
        match (cur p).t with NAME _ -> true | LP -> p.i - 1 = p.stmt_at && is_receiver p && method_line () | _ -> false
      in
      let self, key, fname = if named then definition_name p else [||], "", "<anonymous>" in
      let f =
        in_func p fname pos (fun () ->
            let ps = Array.append self (params p) in
            let ret = match (cur p).t with NAME _ when ends_header p p.i -> Some (type_ref p) | _ -> None in
            let body = block p (fun t -> t = END) in
            expect p END "end";
            ps, ret, body)
      in
      if named then node p pos (Fn_def (name key, f)) else node p pos (Lambda f))

(* What a definition says before its parameters: (r Rect) Area, Rect.Square or a plain name. Gives the object as a parameter,
   the name inside the core, where a static method has the mark that Lexer.split_method reads, and the name to show. *)
and definition_name p =
  let word what =
    match (cur p).t with
    | NAME n -> advance p; n
    | _ -> unexpected p what
  in
  if (cur p).t = LP then begin
    advance p;
    let pname = word "a parameter name" in
    let sname = word "the name of a struct" in
    if (cur p).t = DOT then error p (cur p).pos Messages.method_foreign;
    expect p RP "\")\"";
    let shown = sname ^ "." ^ word "a method name" in
    [| { pname; default = None; ptype = None } |], shown, shown
  end
  else begin
    let n = word "a name" in
    if (cur p).t = DOT then begin
      advance p;
      let at = (cur p).pos in
      let m = word "a method name" in
      if (cur p).t = DOT then error p (cur p).pos Messages.method_foreign;
      if m = "From" then error p at (Messages.from_static n);
      [||], n ^ ":" ^ m, n ^ "." ^ m
    end
    else [||], n, n
  end

(* (params) = expression, or (params) Type = expression, after what [definition_name] gives. *)
and short_def p pos (self, key, fname) =
  let f =
    in_func p fname pos (fun () ->
        let ps = Array.append self (params p) in
        let ret = match (cur p).t with NAME _ -> Some (type_ref p) | _ -> None in
        let eq = cur p in
        expect p ASSIGN "\"=\"";
        skip_nl p;
        let body = expr p in
        ps, ret, hooked p body.pos (node p eq.pos (Return { rvalue = Some body; tail = true })))
  in
  node p pos (Fn_def (name key, f))

and or_expr p =
  let l = ref (and_expr p) in
  while (cur p).t = OR do
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    l := node p pos (Or (!l, and_expr p))
  done;
  !l

and and_expr p =
  let l = ref (not_expr p) in
  while (cur p).t = AND do
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    l := node p pos (And (!l, not_expr p))
  done;
  !l

and not_expr p =
  if (cur p).t = NOT then begin
    let pos = (cur p).pos in
    advance p;
    node p pos (Not (deeper p (fun () -> not_expr p)))
  end else compare p

and compare p =
  let l = range p in
  let op =
    match (cur p).t with
    | EQEQ -> Some Eq | NE -> Some Ne | LT -> Some Lt | LE -> Some Le | GT -> Some Gt | GE -> Some Ge
    | _ -> None
  in
  match op with
  | None ->
    if (cur p).t = IN then begin
      let pos = (cur p).pos in
      advance p;
      skip_nl p;
      node p pos (In_op (l, range p))
    end else l
  | Some op ->
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    node p pos (Bin (op, l, range p))

and range p =
  let l = additive p in
  if (cur p).t = COLON then begin
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    node p pos (Range (l, additive p))
  end else l

(* Inside [ ], [a -b] makes two values: space before the sign, none after. *)
and starts_value p =
  p.mode = Row
  && (let t = cur p in
      t.sp && (t.t = MINUS || t.t = PLUS) && not p.toks.(p.i + 1).sp)

and additive p =
  let l = ref (multiplicative p) in
  let rec go () =
    match (cur p).t with
    | (PLUS | MINUS) when starts_value p -> ()
    | PLUS -> step Add
    | MINUS -> step Sub
    | _ -> ()
  and step op =
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    l := node p pos (Bin (op, !l, multiplicative p));
    go ()
  in
  go ();
  !l

and multiplicative p =
  let l = ref (unary p) in
  let rec go () =
    match (cur p).t with
    | STAR -> step Mul
    | SLASH -> step Div
    | _ -> ()
  and step op =
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    l := node p pos (Bin (op, !l, unary p));
    go ()
  in
  go ();
  !l

and unary p =
  if (cur p).t = MINUS then begin
    let pos = (cur p).pos in
    advance p;
    let a = deeper p (fun () -> unary p) in
    match a.e with
    | Lint i -> node p pos (Lint (-i))
    | Lfloat x -> node p pos (Lfloat (-.x))
    | _ -> node p pos (Neg a)
  end else power p

and power p =
  let base = postfix p in
  if (cur p).t = CARET then begin
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    node p pos (Bin (Pow, base, deeper p (fun () -> unary p)))
  end else base

and postfix p =
  let e = ref (primary p) in
  let rec go () =
    let t = cur p in
    match t.t with
    | LP when not t.sp ->
      advance p;
      let args = it_sugar p (call_args p) in
      e := node p (!e).pos (Call { callee = !e; args; self_tail = false });
      go ()
    | LB when not t.sp ->
      advance p;
      let ixs, uses_end = index_args p in
      e := node p t.pos (Index (!e, ixs, uses_end));
      go ()
    | QUESTION ->
      if t.sp then error p t.pos Messages.question_space;
      if not p.in_function then error p t.pos Messages.question_file;
      advance p;
      e := node p t.pos (Question !e);
      go ()
    | DOT ->
      advance p;
      (match (cur p).t with
       | NAME n ->
         advance p;
         e := node p t.pos (Field (!e, n));
         go ()
       | _ -> unexpected p "a field name")
    | _ -> ()
  in
  go ();
  !e

and call_args p =
  with_mode p Ignore (fun () ->
      let args = ref [] in
      while (cur p).t <> RP do
        (match (cur p).t with
         | NAME n when next_tok p = ASSIGN ->
           advance p;
           advance p;
           args := { aname = Some n; value = expr p } :: !args
         | _ -> args := { aname = None; value = expr p } :: !args);
        if (cur p).t = COMMA then advance p
        else if (cur p).t <> RP then unexpected p "\",\" or \")\""
      done;
      advance p;
      Array.of_list (List.rev !args))

and index_args p =
  with_mode p Ignore (fun () ->
      let saved_end = p.saw_end in
      p.saw_end <- false;
      p.in_index <- p.in_index + 1;
      let out = ref [] in
      while (cur p).t <> RB do
        if (cur p).t = COLON && (next_tok p = COMMA || next_tok p = RB) then begin
          advance p;
          out := All :: !out
        end else out := Ix (expr p) :: !out;
        if (cur p).t = COMMA then advance p
        else if (cur p).t <> RB then unexpected p "\",\" or \"]\""
      done;
      advance p;
      p.in_index <- p.in_index - 1;
      let uses_end = p.saw_end in
      p.saw_end <- saved_end;
      Array.of_list (List.rev !out), uses_end)

(* A pattern. {a, b}, {x: p}, [a, b], a name, _, or a literal. *)
and pattern p =
  let t = cur p in
  match t.t with
  | NAME "_" -> advance p; Pwild
  | NAME n when p.toks.(p.i + 1).t = LP && not p.toks.(p.i + 1).sp ->
    advance p;
    advance p;
    with_mode p Ignore (fun () ->
        let out = ref [] in
        while (cur p).t <> RP do
          out := pattern p :: !out;
          if (cur p).t = COMMA then advance p
          else if (cur p).t <> RP then unexpected p "\",\" or \")\""
        done;
        advance p;
        Pcons (n, Array.of_list (List.rev !out)))
  | NAME n -> advance p; Pname (name n)
  | LB ->
    advance p;
    with_mode p Ignore (fun () ->
        let out = ref [] in
        while (cur p).t <> RB do
          out := pattern p :: !out;
          if (cur p).t = COMMA then advance p
          else if (cur p).t <> RB then unexpected p "\",\" or \"]\""
        done;
        advance p;
        Parray (Array.of_list (List.rev !out)))
  | LC ->
    advance p;
    with_mode p Ignore (fun () ->
        let out = ref [] in
        while (cur p).t <> RC do
          (match (cur p).t with
           | NAME n ->
             advance p;
             if (cur p).t = COLON then begin
               advance p;
               out := (n, pattern p) :: !out
             end else out := (n, Pname (name n)) :: !out
           | _ -> unexpected p "a field name");
          if (cur p).t = COMMA then advance p
          else if (cur p).t <> RC then unexpected p "\",\" or \"}\""
        done;
        advance p;
        Pstruct (Array.of_list (List.rev !out)))
  | INT _ | FLOAT _ | TEXT _ | TRUE | FALSE | MISSING | MINUS -> Plit (unary p)
  | _ -> unexpected p "a pattern"

(* The token after the ] or } matching the current token. *)
and after_close p =
  let k = ref (p.i + 1) and depth = ref 1 in
  while !depth > 0 && p.toks.(!k).t <> EOF do
    (match p.toks.(!k).t with
     | LB | LC | LP -> incr depth
     | RB | RC | RP -> decr depth
     | _ -> ());
    incr k
  done;
  p.toks.(!k).t

(* After {: fields. *)
and struct_lit p pos =
  with_mode p Ignore (fun () ->
      let saved_index = p.in_index in
      p.in_index <- 0;
      match (cur p).t with
      | TEXT _ | INT _ | FLOAT _ | LP -> dict_lit p pos saved_index
      | _ -> fields_lit p pos saved_index)

(* {"a": 1, 2: "b", (key): 3}: a key is a literal, or an expression in parentheses. *)
and dict_lit p pos saved_index =
  let items = ref [] in
  while (cur p).t <> RC do
    let key = primary p in
    expect p COLON "\":\"";
    let value = expr p in
    items := { aname = None; value } :: { aname = None; value = key } :: !items;
    if (cur p).t = COMMA then advance p
    else if (cur p).t <> RC then unexpected p "\",\" or \"}\""
  done;
  advance p;
  p.in_index <- saved_index;
  let args = Array.of_list (List.rev !items) in
  (* Keys that are texts of the code, few and each once, make their keys once, as names do. *)
  let keys = List.filteri (fun i _ -> i mod 2 = 0) (Array.to_list args) in
  let text (a : arg) = match a.value.e with Ltext s -> Some s | _ -> None in
  let names = List.filter_map text keys in
  if List.length names = List.length keys && List.length names <= 32 && List.length (List.sort_uniq String.compare names) = List.length names
  then node p pos (Struct_lit { sname = None; sfields = Array.of_list (List.mapi (fun i n -> n, args.((2 * i) + 1).value) names) })
  else node p pos (Call { callee = node p pos (Var { text = "#dict"; b = Unresolved }); args; self_tail = false })

and fields_lit p pos saved_index =
      let out = ref [] in
      while (cur p).t <> RC do
        (match (cur p).t with
         | NAME n ->
           advance p;
           expect p COLON "\":\"";
           out := (n, expr p) :: !out
         | _ -> unexpected p "a field name");
        if (cur p).t = COMMA then advance p
        else if (cur p).t <> RC then unexpected p "\",\" or \"}\""
      done;
      advance p;
      p.in_index <- saved_index;
      node p pos (Struct_lit { sname = None; sfields = Array.of_list (List.rev !out) })

(* struct Name { field, field = default }, or struct Name and a line end, then one field per line until end: a function
   that builds the struct. *)
and struct_def p pos =
  if p.in_function then error p pos Messages.struct_nested;
  advance p;
  let sname =
    match (cur p).t with
    | NAME n -> advance p; n
    | _ -> unexpected p "a struct name"
  in
  let f =
    in_func p sname pos (fun () ->
        let ps = if p.toks.(p.i).t = NL then field_lines p else listed p LC RC "a field name" in
        (* A field that takes missing has it as its default. *)
        let optional q =
          match q.ptype with
          | Some t when t.topt && q.default = None -> { q with default = Some (node p t.tpos Lmissing) }
          | _ -> q
        in
        let ps = Array.map optional ps in
        let sfields = Array.map (fun q -> q.pname, node p pos (Var (name q.pname))) ps in
        let body = node p pos (Struct_lit { sname = Some sname; sfields }) in
        ps, None, [| node p pos (Return { rvalue = Some body; tail = true }) |])
  in
  node p pos (Fn_def (name sname, f))

(* The fields of the block form, each alone on its line, up to end. *)
and field_lines p =
  with_mode p Lines (fun () ->
      let out = ref [] in
      skip_nl p;
      while (cur p).t <> END do
        if (cur p).t = EOF then unexpected p "end";
        (match (cur p).t, p.toks.(p.i + 1).t with
         | NAME _, (NL | ASSIGN | COMMA | NAME _ | END) -> out := param p "a field name" :: !out
         | _ -> error p (cur p).pos Messages.struct_not_field);
        (match (cur p).t with
         | NL -> skip_nl p
         | COMMA | NAME _ -> error p (cur p).pos Messages.struct_line
         | _ -> unexpected p "the end of the line")
      done;
      advance p;
      Array.of_list (List.rev !out))

(* interface Name { Method(params), ... }, or interface Name and a line end, then one method per line until end. *)
and interface_def p pos =
  if p.in_function || p.depth > 1 then error p pos Messages.interface_nested;
  advance p;
  let iname =
    match (cur p).t with
    | NAME n -> advance p; n
    | _ -> unexpected p "an interface name"
  in
  let imethods =
    if p.toks.(p.i).t <> NL then
      with_mode p Ignore (fun () ->
          expect p LC "\"{\"";
          let out = ref [] in
          while (cur p).t <> RC do
            out := iface_method p :: !out;
            if (cur p).t = COMMA then advance p else if (cur p).t <> RC then unexpected p "\",\" or \"}\""
          done;
          advance p;
          !out)
    else
      with_mode p Lines (fun () ->
          let out = ref [] in
          skip_nl p;
          while (cur p).t <> END do
            if (cur p).t = EOF then unexpected p "end";
            out := iface_method p :: !out;
            (match (cur p).t with
             | NL -> skip_nl p
             | COMMA | NAME _ -> error p (cur p).pos Messages.interface_line
             | _ -> unexpected p "the end of the line")
          done;
          advance p;
          !out)
  in
  node p pos (Interface { iname; imethods = Array.of_list (List.rev imethods) })

(* Name(params) and maybe its return type, with no body and no default. *)
and iface_method p =
  match (cur p).t, next_tok p with
  | NAME n, LP ->
    advance p;
    let ps = params p in
    Array.iter (fun q -> Option.iter (fun (d : expr) -> error p d.pos Messages.interface_default) q.default) ps;
    let ret = match (cur p).t, next_tok p with NAME _, LP -> None | NAME _, _ -> Some (type_ref p) | _ -> None in
    if (cur p).t = ASSIGN then error p (cur p).pos Messages.interface_body;
    n, ps, ret
  | _ -> error p (cur p).pos Messages.interface_not_method

(* After [: rows, or a comprehension. *)
and array_lit p pos =
  with_mode p Row (fun () ->
      let saved_index = p.in_index in
      p.in_index <- 0;
      let rows = ref [] and row = ref [] in
      let end_row () =
        if !row <> [] then begin
          rows := Array.of_list (List.rev !row) :: !rows;
          row := []
        end
      in
      let result = ref None in
      while !result = None do
        let t = cur p in
        match t.t with
        | RB ->
          advance p;
          end_row ();
          result := Some (node p pos (Array_lit (Array.of_list (List.rev !rows))))
        | SEMI | NL -> advance p; end_row ()
        | COMMA -> advance p; skip_nl p
        | FOR when !rows = [] && List.length !row = 1 ->
          advance p;
          let cvar = match (cur p).t with
            | NAME n -> advance p; name n
            | _ -> unexpected p "a variable"
          in
          expect p IN "in";
          let csrc = expr p in
          let cguard =
            if (cur p).t = IF then begin
              advance p;
              Some (expr p)
            end else None
          in
          skip_nl p;
          expect p RB "\"]\"";
          result := Some (node p pos (Comp { cbody = List.hd !row; cvar; csrc; cguard }))
        | _ -> row := expr p :: !row
      done;
      p.in_index <- saved_index;
      Option.get !result)

and primary p =
  let t = cur p in
  let lit e = advance p; node p t.pos e in
  match t.t with
  | INT i -> lit (Lint i)
  | FLOAT x -> lit (Lfloat x)
  | TRUE -> lit (Lbool true)
  | FALSE -> lit (Lbool false)
  | MISSING -> lit Lmissing
  | TEXT parts -> advance p; text p t.pos parts
  | NAME n -> lit (Var (name n))
  | LP ->
    advance p;
    let e = with_mode p Ignore (fun () -> expr p) in
    with_mode p Ignore (fun () -> expect p RP "\")\"");
    e
  | IF -> advance p; with_mode p Lines (fun () -> if_expr p t.pos)
  | WHILE -> advance p; with_mode p Lines (fun () -> while_expr p t.pos)
  | FOR -> advance p; with_mode p Lines (fun () -> for_expr p t.pos)
  | MATCH -> advance p; with_mode p Lines (fun () -> match_expr p t.pos)
  | DEFN -> advance p; function_expr p t.pos
  | LB -> advance p; array_lit p t.pos
  | LC -> advance p; struct_lit p t.pos
  | END when p.in_index > 0 ->
    p.saw_end <- true;
    lit End_index
  | _ -> unexpected p "an expression"

and text p pos parts =
  match parts with
  | [ Plain s ] -> node p pos (Ltext s)
  | _ ->
    let part = function
      | Plain s -> Lit s
      | Code toks ->
        let sub = { p with toks; i = 0; mode = Ignore } in
        let e = expr sub in
        if (cur sub).t <> EOF then unexpected sub "the end of the code";
        p.next_id <- sub.next_id;
        Hole e
    in
    node p pos (Interp (Array.of_list (List.map part parts)))

and if_expr p pos =
  let cond = expr p in
  let yes = block p (fun t -> t = ELSE || t = END) in
  let no =
    if (cur p).t = ELSE then begin
      let else_pos = (cur p).pos in
      advance p;
      if (cur p).t = IF then begin
        advance p;
        [| if_expr p else_pos |]
      end else begin
        let b = block p (fun t -> t = END) in
        expect p END "end";
        b
      end
    end else begin
      expect p END "end";
      [||]
    end
  in
  node p pos (If (cond, yes, no))

and while_expr p pos =
  let cond = expr p in
  let saved = p.loop in
  let flag = ref false in
  p.loop <- Some flag;
  let body = block p (fun t -> t = END) in
  p.loop <- saved;
  expect p END "end";
  node p pos (While { cond; body; has_break = !flag })

and match_expr p pos =
  let saved = p.in_index in
  p.in_index <- 0;
  let subject = expr p in
  let arms = ref [] in
  skip_nl p;
  while (cur p).t <> END do
    if (cur p).t = ELSE then begin
      advance p;
      expect p ARROW "\"->\"";
      skip_nl p;
      arms := { pt = Pwild; guard = None; abody = expr p } :: !arms
    end else begin
      let pt = pattern p in
      let guard =
        if (cur p).t = IF then begin
          advance p;
          Some (then_expr p)
        end else None
      in
      expect p ARROW "\"->\"";
      skip_nl p;
      arms := { pt; guard; abody = expr p } :: !arms
    end;
    skip_nl p
  done;
  advance p;
  p.in_index <- saved;
  node p pos (Match { subject; arms = Array.of_list (List.rev !arms) })

and for_expr p pos =
  let var =
    match (cur p).t with
    | NAME n -> advance p; name n
    | _ -> unexpected p "a variable"
  in
  expect p IN "in";
  let iter = expr p in
  let saved = p.loop in
  let flag = ref false in
  p.loop <- Some flag;
  let fbody = block p (fun t -> t = END) in
  p.loop <- saved;
  expect p END "end";
  node p pos (For { var; iter; fbody; f_break = !flag })

and block p stop =
  with_mode p Lines (fun () ->
      deeper p (fun () ->
          let saved_index = p.in_index in
          p.in_index <- 0;
          let items = ref [] in
          skip_nl p;
          while not (stop (cur p).t) do
            if (cur p).t = EOF then unexpected p "end";
            let pos = (cur p).pos in
            let s = stmt p in
            (* A file-level definition and a use run nothing: no stop on them. *)
            (match s.e with
             | Fn_def _ when not p.in_function -> ()
             | Use _ | Interface _ -> ()
             | _ -> if p.hooks then items := hook p pos :: !items);
            items := s :: !items;
            skip_nl p
          done;
          p.in_index <- saved_index;
          Array.of_list (List.rev !items)))

(* Is the ( at token k the start of name(params) = expression, or name(params) Type = expression? *)
and after_call_is_def p k =
  let saved = p.i in
  p.i <- k;
  let j = paren_end p in
  p.i <- saved;
  p.toks.(type_end p j).t = ASSIGN

(* Rect.Unit() = ... *)
and short_method p =
  (not p.in_function)
  && next_tok p = DOT
  && (match p.toks.(p.i + 2).t with NAME _ -> true | _ -> false)
  && (let t = p.toks.(p.i + 3) in t.t = LP && not t.sp)
  && after_call_is_def p (p.i + 3)

and stmt p =
  let t = cur p in
  p.stmt_at <- p.i;
  match t.t with
  | BREAK ->
    (match p.loop with
     | Some flag -> flag := true
     | None -> error p t.pos Messages.break_outside);
    advance p;
    node p t.pos Break
  | STRUCT -> struct_def p t.pos
  | INTERFACE -> interface_def p t.pos
  | USE ->
    if p.in_function then error p t.pos Messages.use_nested;
    advance p;
    let start = (cur p).pos in
    (* A folder before the last part may hold - and . with no space around them, as www-celestial or gitlab.com in
       deps/www-celestial/cesia-lang/x and deps/gitlab.com/x/y/z. The last part is the name in the code. *)
    let rec glued n =
      let t = cur p and after = p.toks.(p.i + 1) in
      match t.t, after.t with
      | (MINUS | DOT), NAME m when (not t.sp) && not after.sp ->
        advance p;
        advance p;
        glued (n ^ (if t.t = MINUS then "-" else ".") ^ m)
      | _ -> n
    in
    let rec path_from acc =
      match (cur p).t with
      | NAME n ->
        advance p;
        let start = p.i in
        let n' = glued n in
        if (cur p).t = SLASH then begin
          advance p;
          path_from (acc ^ n' ^ "/")
        end
        else begin
          p.i <- start;
          acc ^ n
        end
      | DOT -> error p start Messages.use_relative
      | TEXT [ Plain s ] -> error p start (Messages.use_quoted s)
      | _ -> unexpected p "a package name"
    in
    let upath = path_from "" in
    let default = Filename.basename upath in
    let ualias =
      match (cur p).t with
      | NAME "as" ->
        advance p;
        (match (cur p).t with
         | NAME n -> advance p; n
         | _ -> unexpected p "a name")
      | _ -> default
    in
    node p start (Use { upath; ualias })
  | (LB | LC) when after_close p = ASSIGN ->
    let pt = pattern p in
    let pos = (cur p).pos in
    advance p;
    skip_nl p;
    node p pos (Destructure (pt, expr p))
  | RETURN ->
    if not p.in_function then error p t.pos Messages.return_outside;
    advance p;
    let next = (cur p).t in
    let rvalue = if next = NL || next = END || next = ELSE || next = EOF then None else Some (expr p) in
    node p t.pos (Return { rvalue; tail = false })
  | NAME _ when next_tok p = LP && not p.toks.(p.i + 1).sp && after_call_is_def p (p.i + 1) ->
    short_def p t.pos (definition_name p)
  | NAME _ when short_method p -> short_def p t.pos (definition_name p)
  | LP when is_receiver p -> short_def p t.pos (definition_name p)
  | _ ->
    let e = expr p in
    (* The path of a write: a variable, followed by indexes and fields. *)
    let rec path (e : expr) acc =
      match e.e with
      | Var { text = "it"; _ } -> error p e.pos Messages.it_assign
      | Var n -> n, acc
      | Index (b, ixs, u) -> path b ({ sp = e.pos; sk = Sindex (ixs, u) } :: acc)
      | Field (b, n) -> path b ({ sp = e.pos; sk = Sfield n } :: acc)
      | _ -> error p (cur p).pos Messages.cant_assign
    in
    let assign_to pos rhs =
      match path e [] with
      | n, [] -> node p pos (Assign (name n.text, rhs))
      | n, steps -> node p pos (Set { root = name n.text; path = Array.of_list steps; value = rhs })
    in
    let update op =
      ignore (path e []);
      let pos = (cur p).pos in
      advance p;
      skip_nl p;
      let rhs = expr p in
      let read =
        match e.e with
        | Var n -> node p e.pos (Var (name n.text))
        | _ -> e
      in
      assign_to pos (node p pos (Bin (op, read, rhs)))
    in
    match (cur p).t with
    | ASSIGN ->
      ignore (path e []);
      let pos = (cur p).pos in
      advance p;
      skip_nl p;
      let rhs = expr p in
      assign_to pos rhs
    | PLUSEQ -> update Add
    | MINUSEQ -> update Sub
    | STAREQ -> update Mul
    | SLASHEQ -> update Div
    | _ -> e

let program ?(hooks = false) ~file ~nesting toks =
  let p = { toks; file; nesting; hooks; i = 0; depth = 0; mode = Lines; next_id = 0; loop = None; in_function = false;
            in_index = 0; saw_end = false; stmt_at = 0 } in
  let body = block p (fun t -> t = EOF) in
  { fname = ""; params = [||]; ret = None; body; nnodes = p.next_id; fpos = Pos.make 1 1; nvars = 0; var_names = [||];
    captures = [||]; maybe_undef = [||]; has_return = false; has_self_tail = false; kept = 0; cell_of = [||];
    export_of = [||] }
