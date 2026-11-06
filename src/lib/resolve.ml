open Ast

let load_error file pos (m : Messages.t) = Pos.Load_error { file; pos; kind = "name"; text = m.text; hint = m.hint }

type kind = File | Named | Anon

type scope = {
  fn : func;
  kind : kind;
  parent : scope option;
  vars : (string, int) Hashtbl.t;
  mutable names : string list;  (* reversed *)
  mutable caps : (int * int) list;
  mutable overlay : (string * int) list;  (* comprehension variables *)
}

type env = {
  path : string;
  m : int;
  lookup : string -> binding option;
  spaces : (string * (string -> binding option)) list;  (* the names of use *)
  hoisted : (string, int) Hashtbl.t;
  structs : (string, (string * expr) array) Hashtbl.t;  (* those of this file and of its package, with their fields *)
  interfaces : (string, unit) Hashtbl.t;  (* those of this file and of its package *)
  is_type : binding -> bool;  (* a struct or an interface of a package already loaded *)
  home : string -> string option;  (* the package of std/ of a name that no file defines, for its message *)
  cells : (string, int) Hashtbl.t;
  mutable cell_list : string list;
  report : exn -> unit;  (* raises when a program loads; a check records the error and goes on *)
}

let fail env pos m = env.report (load_error env.path pos m)

let new_var sc text =
  let i = Hashtbl.length sc.vars in
  Hashtbl.add sc.vars text i;
  sc.names <- text :: sc.names;
  i

let var sc text =
  match Hashtbl.find_opt sc.vars text with
  | Some i -> i
  | None -> new_var sc text

(* A comprehension variable: an internal name no ordinary read can find. *)
let fresh sc text = new_var sc (Printf.sprintf "%s#%d" text (Hashtbl.length sc.vars))

let cell env text =
  match Hashtbl.find_opt env.cells text with
  | Some k -> k
  | None ->
    let k = Hashtbl.length env.cells in
    Hashtbl.add env.cells text k;
    env.cell_list <- text :: env.cell_list;
    k

let rec pat_names f = function
  | Pname n -> f n
  | Pwild | Plit _ -> ()
  | Parray ps | Pcons { cargs = ps; _ } -> Array.iter (pat_names f) ps
  | Pstruct fs -> Array.iter (fun (_, q) -> pat_names f q) fs

let rec pat_exprs f = function
  | Plit e -> f e
  | Pname _ | Pwild -> ()
  | Parray ps | Pcons { cargs = ps; _ } -> Array.iter (pat_exprs f) ps
  | Pstruct fs -> Array.iter (fun (_, q) -> pat_exprs f q) fs

(* The subexpressions, without entering nested functions. *)
let children (f : expr -> unit) (e : expr) =
  let index = function All -> () | Ix e -> f e in
  match e.e with
  | Bin (_, a, b) | And (a, b) | Or (a, b) | Range (a, b) | In_op (a, b) -> f a; f b
  | Neg a | Not a | Field (a, _) | Question a -> f a
  | Assign (_, v) | Destructure (_, v) -> f v
  | Struct_lit { sfields; _ } -> Array.iter (fun (_, v) -> f v) sfields
  | Call { callee; args; _ } -> f callee; Array.iter (fun a -> f a.value) args
  | If (c, a, b) -> f c; Array.iter f a; Array.iter f b
  | While { cond; body; _ } -> f cond; Array.iter f body
  | For { iter; fbody; _ } -> f iter; Array.iter f fbody
  | Interp parts -> Array.iter (function Hole e -> f e | Lit _ -> ()) parts
  | Return { rvalue = Some v; _ } -> f v
  | Array_lit rows -> Array.iter (Array.iter f) rows
  | Comp { cbody; csrc; cguard; _ } -> f csrc; f cbody; Option.iter f cguard
  | Index (b, ixs, _) -> f b; Array.iter index ixs
  | Set { path; value; _ } ->
    Array.iter (fun st -> match st.sk with Sindex (ixs, _) -> Array.iter index ixs | Sfield _ -> ()) path;
    f value
  | Match { subject; arms } ->
    f subject;
    Array.iter
      (fun a ->
         pat_exprs f a.pt;
         Option.iter f a.guard;
         f a.abody)
      arms
  | Return _ | Lambda _ | Fn_def _ | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ | Var _ | Break | End_index | Use _
  | Interface _ | Hook _ -> ()

(* The assigned names, without entering nested functions. *)
let rec assigned sc (e : expr) =
  match e.e with
  | Assign (n, _) -> ignore (var sc n.text); children (assigned sc) e
  | Set { root; _ } -> ignore (var sc root.text); children (assigned sc) e
  | Destructure (pt, _) -> pat_names (fun n -> ignore (var sc n.text)) pt; children (assigned sc) e
  | Match { arms; _ } ->
    Array.iter (fun a -> pat_names (fun n -> ignore (var sc n.text)) a.pt) arms;
    children (assigned sc) e
  | For { var = v; _ } -> ignore (var sc v.text); children (assigned sc) e
  | Fn_def (n, _) -> ignore (var sc n.text)
  | _ -> children (assigned sc) e

(* A variable of an enclosing scope. *)
let rec find env sc celled text : binding option =
  match List.assoc_opt text sc.overlay with
  | Some i -> Some (Local i)
  | None ->
  match Hashtbl.find_opt sc.vars text with
  | Some i -> Some (Local i)
  | None ->
    match sc.parent with
    | None ->
      (match Hashtbl.find_opt env.hoisted text with
       | Some k -> Some (Cell { m = env.m; k; stable = true })
       | None -> None)
    | Some parent ->
      if parent.kind = File && (sc.kind = Named || Hashtbl.mem env.hoisted text) then begin
        match Hashtbl.find_opt env.hoisted text with
        | Some k -> Some (Cell { m = env.m; k; stable = true })
        | None ->
          if Hashtbl.mem parent.vars text then begin
            celled := text :: !celled;
            Some (Cell { m = env.m; k = cell env text; stable = false })
          end else None
      end else begin
        match find env parent celled text with
        | Some (Local outer) ->
          let inner = new_var sc text in
          sc.caps <- (outer, inner) :: sc.caps;
          Some (Local inner)
        | other -> other
      end

(* Rect.Area, or Rect.Nope, where Rect is a struct and no object. *)
let struct_member env pos sname name =
  let exists text =
    Hashtbl.mem env.hoisted text || env.lookup text <> None || List.exists (fun (_, look) -> look text <> None) env.spaces
  in
  if exists (sname ^ "." ^ name) then fail env pos (Messages.needs_object sname name);
  if Hashtbl.mem env.structs sname && name <> "From" then fail env pos (Messages.no_static sname name)

(* The static method that Rect.Square or date.Date.Parse name, if they name one. A variable called like the struct or the
   module hides it: piece.Size stays a field. *)
let static env sc celled (base : expr) name =
  let in_space sname look =
    let text = sname ^ ":" ^ name in
    Option.map (fun b -> { text; b }) (look text)
  in
  match base.e with
  | Var { text = sname; _ } ->
    (match find env sc celled sname with
     | Some (Local _) -> None
     | _ ->
       in_space sname (fun text ->
           match find env sc celled text with
           | Some b -> Some b
           | None -> env.lookup text))
  | Field ({ e = Var { text = alias; _ }; _ }, sname)
    when Lexer.is_public sname && Lexer.is_public name && find env sc celled alias = None ->
    Option.bind (List.assoc_opt alias env.spaces) (in_space sname)
  | _ -> None

(* A name that no file defines: when a package of std/ has it, the message says which use to write. *)
let undefined env name = match env.home name with Some p -> Messages.moved name p | None -> Messages.undefined name

(* The struct that a pattern names is one the file sees, as any name: Point of its package, geo.Point of a package it uses. *)
let rec constructors env sc celled = function
  | Pcons { cpkg; cname; cargs; cpos } ->
    (match cpkg with
     | Some alias when List.mem_assoc alias env.spaces && find env sc celled alias = None ->
       (match if Lexer.is_public cname then (List.assoc alias env.spaces) cname else None with
        (* Unresolved: a package that a check couldn't read, whose error is at its use. *)
        | Some b when b = Unresolved || env.is_type b -> ()
        | Some _ -> fail env cpos (Messages.pattern_struct (alias ^ "." ^ cname))
        | None -> fail env cpos (Messages.no_name alias cname))
     | Some alias -> fail env cpos (Messages.undefined alias)
     | None ->
       let seen = match env.lookup cname with Some b -> env.is_type b | None -> false in
       if not (Hashtbl.mem env.structs cname || seen) then
         fail env cpos (match env.home cname with Some p -> Messages.moved cname p | None -> Messages.pattern_struct cname));
    Array.iter (constructors env sc celled) cargs
  | Parray ps -> Array.iter (constructors env sc celled) ps
  | Pstruct fs -> Array.iter (fun (_, q) -> constructors env sc celled q) fs
  | Pname _ | Pwild | Plit _ -> ()

let kinds = [ "Int"; "Float"; "Number"; "Bool"; "Text"; "Array"; "Dict"; "Function" ]

(* A type: a kind, or a struct or an interface of this package or of a package the file uses, found as other names are. *)
let type_ref env (t : ptype) =
  if not (t.tpkg = None && List.mem t.tname kinds) then begin
    let found =
      match t.tpkg with
      | None ->
        (match Hashtbl.find_opt env.hoisted t.tname with
         | Some k -> Some (Cell { m = env.m; k; stable = true })
         | None -> env.lookup t.tname)
      | Some alias ->
        if Lexer.is_public t.tname then Option.bind (List.assoc_opt alias env.spaces) (fun look -> look t.tname) else None
    in
    let is_here name = Hashtbl.mem env.structs name || Hashtbl.mem env.interfaces name in
    let here = t.tpkg = None && (Hashtbl.mem env.hoisted t.tname || is_here t.tname) in
    match found with
    | Some Unresolved when t.tpkg <> None -> ()
    | Some b when (if here then is_here t.tname else env.is_type b) -> t.tb <- b
    | _ ->
      let shown = match t.tpkg with Some alias -> alias ^ "." ^ t.tname | None -> t.tname in
      fail env t.tpos (match t.tpkg, env.home t.tname with None, Some p -> Messages.moved t.tname p | _ -> Messages.no_type shown)
  end

let rec reads env sc celled (e : expr) =
  let go = reads env sc celled in
  match e.e with
  | Field ({ e = Var { text; _ }; _ }, name)
    when List.mem_assoc text env.spaces && find env sc celled text = None ->
    (* r.name: a variable of another module. *)
    let found = if Lexer.is_public name then (List.assoc text env.spaces) name else None in
    (match found with
     | Some b -> e.e <- Var { text = name; b }
     | None -> fail env e.pos (Messages.no_name text name))
  | Field (base, name) ->
    (match static env sc celled base name with
     | Some method_name -> e.e <- Var method_name
     | None ->
       (* geo.Rect.small: a static method of another package; a field is checked when it is read. *)
       (match base.e with
        | Field ({ e = Var { text = alias; _ }; _ }, sname) when not (Lexer.is_public name) && find env sc celled alias = None ->
          (match Option.bind (List.assoc_opt alias env.spaces) (fun look -> look sname) with
           | Some b when env.is_type b -> fail env e.pos (Messages.private_member name)
           | _ -> ())
        | _ -> ());
       children go e;
       (match base.e with
        | Var { b = Cell { stable = true; _ }; text } -> struct_member env e.pos text name
        | _ -> ()))
  | Var n ->
    (match find env sc celled n.text with
     | Some b -> n.b <- b
     | None ->
       match env.lookup n.text with
       | Some b -> n.b <- b
       | None -> fail env e.pos (undefined env n.text))
  | Assign (n, _) -> n.b <- Local (var sc n.text); children go e
  | Set { root; path; _ } ->
    root.b <- Local (var sc root.text);
    children go e
  | Destructure (pt, _) ->
    constructors env sc celled pt;
    pat_names (fun n -> n.b <- Local (var sc n.text)) pt;
    children go e
  | Match { arms; _ } ->
    Array.iter (fun a -> constructors env sc celled a.pt; pat_names (fun n -> n.b <- Local (var sc n.text)) a.pt) arms;
    children go e
  | For { var = v; _ } -> v.b <- Local (var sc v.text); children go e
  | Comp { cbody; cvar; csrc; cguard } ->
    go csrc;
    let i = fresh sc cvar.text in
    cvar.b <- Local i;
    let saved = sc.overlay in
    sc.overlay <- (cvar.text, i) :: saved;
    go cbody;
    Option.iter go cguard;
    sc.overlay <- saved
  | Fn_def (n, f) ->
    if Lexer.split_method n.text <> None then fail env e.pos Messages.method_nested;
    n.b <- Local (var sc n.text);
    func env (Some sc) Anon celled f
  | Lambda f -> func env (Some sc) Anon celled f
  | _ -> children go e

and func env parent kind celled (f : func) =
  let sc = { fn = f; kind; parent; vars = Hashtbl.create 8; names = []; caps = []; overlay = [] } in
  Array.iter (fun p -> ignore (new_var sc p.pname)) f.params;
  Array.iter (fun p -> Option.iter (type_ref env) p.ptype) f.params;
  Option.iter (type_ref env) f.ret;
  Array.iter (assigned sc) f.body;
  Array.iter (fun p -> Option.iter (reads env sc celled) p.default) f.params;
  Array.iter (reads env sc celled) f.body;
  finish sc

and finish sc =
  let f = sc.fn in
  f.nvars <- Hashtbl.length sc.vars;
  f.var_names <- Array.of_list (List.rev sc.names);
  f.captures <- Array.of_list (List.rev sc.caps);
  flow f

(* Definite assignment: a variable read without being surely assigned is marked. *)
and flow (f : func) =
  let n = f.nvars in
  let undef = Array.make n false in
  let all () = Bytes.make n '\001' in
  let set = ref (Bytes.make n '\000') in
  Array.iteri (fun i _ -> Bytes.set !set i '\001') f.params;
  Array.iter (fun (_, inner) -> undef.(inner) <- true; Bytes.set !set inner '\001') f.captures;
  let inter a b =
    Bytes.mapi (fun i c -> if c = '\001' && Bytes.get b i = '\001' then '\001' else '\000') a
  in
  let branch f =
    let saved = !set in
    set := Bytes.copy saved;
    f ();
    let after = !set in
    set := saved;
    after
  in
  let rec go (e : expr) =
    match e.e with
    | Hook h -> h.live <- Bytes.copy !set
    | Var { b = Local i; _ } -> if Bytes.get !set i = '\000' then undef.(i) <- true
    | Assign ({ b = Local i; _ }, v) -> go v; Bytes.set !set i '\001'
    | Set { root = { b = Local i; _ }; _ } ->
      if Bytes.get !set i = '\000' then undef.(i) <- true;
      children go e
    | Fn_def ({ b = Local i; _ }, g) -> capture g; Bytes.set !set i '\001'
    | Lambda g -> capture g
    | Destructure (pt, v) ->
      go v;
      pat_names (fun n -> match n.b with Local i -> Bytes.set !set i '\001' | _ -> ()) pt
    | And (a, b) | Or (a, b) ->
      go a;
      ignore (branch (fun () -> go b))
    | If (c, a, b) ->
      go c;
      let after_a = branch (fun () -> Array.iter go a) in
      let after_b = branch (fun () -> Array.iter go b) in
      set := inter after_a after_b
    | While { cond; body; _ } ->
      go cond;
      ignore (branch (fun () -> Array.iter go body))
    | For { var = { b = Local i; _ }; iter; fbody; _ } ->
      go iter;
      ignore (branch (fun () -> Bytes.set !set i '\001'; Array.iter go fbody))
    | Comp { cbody; cvar = { b = Local i; _ }; csrc; cguard } ->
      go csrc;
      ignore (branch (fun () ->
          Bytes.set !set i '\001';
          Option.iter go cguard;
          go cbody))
    | Match { subject; arms } ->
      go subject;
      let after =
        Array.map
          (fun a ->
             branch (fun () ->
                 pat_names (fun n -> match n.b with Local i -> Bytes.set !set i '\001' | _ -> ()) a.pt;
                 Option.iter go a.guard;
                 go a.abody))
          arms
      in
      if Array.length after > 0 then set := Array.fold_left inter after.(0) after
    | Return r -> Option.iter go r.rvalue; set := all ()
    | Break -> set := all ()
    | _ -> children go e
  and capture (g : func) =
    Array.iter (fun (outer, _) -> if Bytes.get !set outer = '\000' then undef.(outer) <- true) g.captures
  in
  Array.iter go f.body;
  f.maybe_undef <- undef

(* The mask has 62 bits: past them, every parameter counts as kept. *)
let keeps (f : func) k = k >= 62 || f.kept land (1 lsl k) <> 0
let keep (f : func) k = if k < Array.length f.params && k < 62 then f.kept <- f.kept lor (1 lsl k)

let rec note_writes (f : func) (e : expr) =
  (match e.e with
   | Set { root = { b = Local k; _ }; _ } | Assign ({ b = Local k; _ }, _) -> keep f k
   | _ -> ());
  children (note_writes f) e

(* Tail positions: a return costs nothing there, a call to itself becomes a loop. A variable returned there stays owned,
   so a parameter that is must not be lent. *)
let rec mark_tail self (f : func) (e : expr) =
  match e.e with
  | Var { b = Local k; _ } -> keep f k
  | Return r ->
    r.tail <- true;
    Option.iter (mark_tail self f) r.rvalue
  | If (_, a, b) ->
    mark_block self f a;
    mark_block self f b
  | Match { arms; _ } -> Array.iter (fun a -> mark_tail self f a.abody) arms
  | Call c ->
    (match c.callee.e, self with
     | Var { b = Cell { k; stable = true; _ }; _ }, Some me
       when k = me && Array.length c.args = Array.length f.params
            && Array.for_all (fun a -> a.aname = None) c.args ->
       c.self_tail <- true;
       f.has_self_tail <- true
     | _ -> ())
  | _ -> ()

and mark_block self f (b : block) =
  if Array.length b > 0 then mark_tail self f b.(Array.length b - 1)

(* After [mark_tail]: is there a return that needs an exception? *)
let rec nontail (e : expr) =
  match e.e with
  | Return { tail = false; _ } | Question _ -> true
  | _ ->
    let found = ref false in
    children (fun x -> if nontail x then found := true) e;
    !found

(* The nested functions of a function, to mark tail positions in them. *)
let rec finish_tail self (f : func) =
  mark_block self f f.body;
  f.has_return <- Array.exists nontail f.body;
  Array.iter (note_writes f) f.body;
  Array.iter (fun p -> Option.iter (note_writes f) p.default) f.params;
  Array.iter nested f.body;
  Array.iter (fun p -> Option.iter nested p.default) f.params

and nested (e : expr) =
  match e.e with
  | Lambda g -> finish_tail None g
  | Fn_def ({ b = Local _; _ }, g) -> finish_tail None g
  | Fn_def _ -> ()
  | _ -> children nested e

(* The fields of a constructor, which is how a struct looks once parsed. *)
let struct_fields (f : func) =
  match f.body with
  | [| { e = Return { rvalue = Some { e = Struct_lit { sname = Some _; sfields }; _ }; _ }; _ } |] -> Some sfields
  | _ -> None

let check_method env pos sname static name =
  match Hashtbl.find_opt env.structs sname with
  | None when Hashtbl.mem env.interfaces sname -> ()
  | None -> fail env pos (Messages.method_no_struct sname)
  | Some sfields ->
    if Array.exists (fun (field, _) -> String.equal field name) sfields then
      fail env pos (Messages.method_field sname name);
    if Hashtbl.mem env.hoisted (sname ^ (if static then "." else ":") ^ name) then
      fail env pos (Messages.method_both sname name)

(* What a file defines for its package: the name inside the core, the name to show, where, and whether it is a function. The
   variable of a loop stays in its file. *)
let definitions (fn : func) =
  let out = ref [] in
  let add text shown pos is_function = out := (text, shown, pos, is_function) :: !out in
  Array.iter
    (fun (e : expr) ->
       match e.e with
       | Fn_def (n, f) -> add n.text f.fname e.pos true
       | Interface i -> add i.iname i.iname e.pos true
       | Assign (n, _) -> add n.text n.text e.pos false
       | Destructure (pt, _) -> pat_names (fun n -> add n.text n.text e.pos false) pt
       | _ -> ())
    fn.body;
  List.rev !out

let check_package ?(report = raise) files =
  let seen = Hashtbl.create 64 in
  let check path (text, shown, pos, _) =
    (match Hashtbl.find_opt seen text with
     | Some (other, at) when not (String.equal other path) ->
       report (load_error path pos (Messages.package_twice shown other (Pos.line at)))
     | _ -> ());
    (match Lexer.split_method text with
     | Some (sname, static, name) when Hashtbl.mem seen (sname ^ (if static then "." else ":") ^ name) ->
       report (load_error path pos (Messages.method_both sname name))
     | _ -> ());
    if not (Hashtbl.mem seen text) then Hashtbl.add seen text (path, pos)
  in
  List.iter (fun (path, fn) -> List.iter (check path) (definitions fn)) files

let file ?(keep = [||]) ?(peers = []) ?(is_type = fun _ -> false) ?(home = fun _ -> None) ?(report = raise) ~file:path ~m
    ~lookup ~spaces (fn : func) =
  let env =
    { path; m; lookup; spaces; hoisted = Hashtbl.create 16; structs = Hashtbl.create 8;
      interfaces = Hashtbl.create 4; is_type; home; cells = Hashtbl.create 16;
      cell_list = []; report }
  in
  Array.iter (fun text -> ignore (cell env text)) keep;
  let sc = { fn; kind = File; parent = None; vars = Hashtbl.create 16; names = []; caps = []; overlay = [] } in
  let hoisted = ref [] and defined = ref [] and interfaces = ref [] in
  List.iter
    (fun (peer : func) ->
       Array.iter
         (fun (e : expr) ->
            match e.e with
            | Fn_def (n, f) -> Option.iter (Hashtbl.replace env.structs n.text) (struct_fields f)
            | Interface i -> Hashtbl.replace env.interfaces i.iname ()
            | _ -> ())
         peer.body)
    peers;
  let hoist (e : expr) text shown =
    if Hashtbl.mem env.hoisted text then fail env e.pos (Messages.duplicate shown);
    let k = cell env text in
    Hashtbl.add env.hoisted text k;
    k
  in
  Array.iter
    (fun (e : expr) ->
       match e.e with
       | Fn_def (n, f) ->
         let k = hoist e n.text f.fname in
         hoisted := (k, f) :: !hoisted;
         Option.iter (Hashtbl.replace env.structs n.text) (struct_fields f);
         Option.iter (fun it -> defined := (e.pos, it, k) :: !defined) (Lexer.split_method n.text)
       | Interface i ->
         interfaces := (hoist e i.iname i.iname, i) :: !interfaces;
         Hashtbl.replace env.interfaces i.iname ()
       | _ -> ())
    fn.body;
  let method_types (_, ps, ret) =
    Array.iter (fun p -> Option.iter (type_ref env) p.ptype) ps;
    Option.iter (type_ref env) ret
  in
  List.iter (fun (_, i) -> Array.iter method_types i.imethods) !interfaces;
  let methods =
    List.rev_map
      (fun (pos, (sname, static, name), k) ->
         check_method env pos sname static name;
         sname, name, static, k)
      !defined
  in
  let top_hoisted (e : expr) = match e.e with Fn_def _ | Interface _ -> true | _ -> false in
  Array.iter (fun e -> if not (top_hoisted e) then assigned sc e) fn.body;
  Hashtbl.iter
    (fun text _ ->
       if Hashtbl.mem env.hoisted text then fail env fn.fpos (Messages.assign_function text))
    sc.vars;
  (* Another file of the package can read a variable while this one runs. *)
  let celled = ref (if peers = [] then [] else Array.to_list keep) in
  Array.iter (fun (e : expr) ->
      match e.e with
      | Fn_def (n, f) ->
        n.b <- Cell { m; k = Hashtbl.find env.hoisted n.text; stable = true };
        func env (Some sc) Named celled f
      | _ -> ())
    fn.body;
  Array.iter (fun e -> if not (top_hoisted e) then reads env sc celled e) fn.body;
  finish sc;
  ignore top_hoisted;
  (* Every file variable has a cell, for export. Those read by a named function live there. *)
  fn.cell_of <- Array.make fn.nvars (-1);
  Array.iteri (fun i text -> if List.mem text !celled then fn.cell_of.(i) <- cell env text) fn.var_names;
  fn.export_of <- Array.map (fun text -> cell env text) fn.var_names;
  Array.iter (fun (e : expr) ->
      match e.e with
      | Fn_def ({ b = Cell { k; _ }; _ }, f) -> finish_tail (Some k) f
      | _ -> ())
    fn.body;
  Array.iter nested fn.body;
  fn.has_return <- false;
  { cell_names = Array.of_list (List.rev env.cell_list); hoisted = Array.of_list (List.rev !hoisted); methods;
    interfaces = List.rev !interfaces }
