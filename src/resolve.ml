open Ast

let error file pos (m : Messages.t) =
  raise (Pos.Load_error { file; pos; kind = "name"; text = m.text; hint = m.hint })

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
  cells : (string, int) Hashtbl.t;
  mutable cell_list : string list;
}

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
  | Parray ps -> Array.iter (pat_names f) ps
  | Pstruct fs -> Array.iter (fun (_, q) -> pat_names f q) fs

let rec pat_exprs f = function
  | Plit e -> f e
  | Pname _ | Pwild -> ()
  | Parray ps -> Array.iter (pat_exprs f) ps
  | Pstruct fs -> Array.iter (fun (_, q) -> pat_exprs f q) fs

(* The subexpressions, without entering nested functions. *)
let children (f : expr -> unit) (e : expr) =
  let index = function All -> () | Ix e -> f e in
  match e.e with
  | Bin (_, a, b) | And (a, b) | Or (a, b) | Range (a, b) | In_op (a, b) -> f a; f b
  | Neg a | Not a | Field (a, _) -> f a
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
  | Try { tbody; handler; _ } -> Array.iter f tbody; Array.iter f handler
  | Return _ | Lambda _ | Fn_def _ | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ | Var _ | Break | End_index | Use _ | Hook _ -> ()

(* The assigned names, without entering nested functions. *)
let rec assigned sc (e : expr) =
  match e.e with
  | Assign (n, _) -> ignore (var sc n.text); children (assigned sc) e
  | Set { root; _ } -> ignore (var sc root.text); children (assigned sc) e
  | Destructure (pt, _) -> pat_names (fun n -> ignore (var sc n.text)) pt; children (assigned sc) e
  | Match { arms; _ } ->
    Array.iter (fun a -> pat_names (fun n -> ignore (var sc n.text)) a.pt) arms;
    children (assigned sc) e
  | Try { ename; _ } ->
    Option.iter (fun n -> ignore (var sc n.text)) ename;
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

let rec reads env sc celled (e : expr) =
  let go = reads env sc celled in
  match e.e with
  | Field ({ e = Var { text; _ }; _ }, name)
    when List.mem_assoc text env.spaces && find env sc celled text = None ->
    (* r.name: a variable of another module. *)
    let found = if String.starts_with ~prefix:"_" name then None else (List.assoc text env.spaces) name in
    (match found with
     | Some b -> e.e <- Var { text = name; b }
     | None -> error env.path e.pos (Messages.no_name text name))
  | Var n ->
    (match find env sc celled n.text with
     | Some b -> n.b <- b
     | None ->
       match env.lookup n.text with
       | Some b -> n.b <- b
       | None -> error env.path e.pos (Messages.undefined n.text))
  | Assign (n, _) -> n.b <- Local (var sc n.text); children go e
  | Set { root; _ } -> root.b <- Local (var sc root.text); children go e
  | Destructure (pt, _) -> pat_names (fun n -> n.b <- Local (var sc n.text)) pt; children go e
  | Match { arms; _ } ->
    Array.iter (fun a -> pat_names (fun n -> n.b <- Local (var sc n.text)) a.pt) arms;
    children go e
  | Try { ename; _ } ->
    Option.iter (fun n -> n.b <- Local (var sc n.text)) ename;
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
    n.b <- Local (var sc n.text);
    func env (Some sc) Anon celled f
  | Lambda f -> func env (Some sc) Anon celled f
  | _ -> children go e

and func env parent kind celled (f : func) =
  let sc = { fn = f; kind; parent; vars = Hashtbl.create 8; names = []; caps = []; overlay = [] } in
  Array.iter (fun p -> ignore (new_var sc p.pname)) f.params;
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
    | Try { tbody; ename; handler } ->
      let body_end = branch (fun () -> Array.iter go tbody) in
      let handler_end =
        branch (fun () ->
            (match ename with
             | Some { b = Local i; _ } -> Bytes.set !set i '\001'
             | _ -> ());
            Array.iter go handler)
      in
      set := inter body_end handler_end
    | Return r -> Option.iter go r.rvalue; set := all ()
    | Break -> set := all ()
    | _ -> children go e
  and capture (g : func) =
    Array.iter (fun (outer, _) -> if Bytes.get !set outer = '\000' then undef.(outer) <- true) g.captures
  in
  Array.iter go f.body;
  f.maybe_undef <- undef

(* Tail positions: a return costs nothing there, a call to itself becomes a loop. *)
let rec mark_tail self (f : func) (e : expr) =
  match e.e with
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
  | Return { tail = false; _ } -> true
  | _ ->
    let found = ref false in
    children (fun x -> if nontail x then found := true) e;
    !found

(* The nested functions of a function, to mark tail positions in them. *)
let rec finish_tail self (f : func) =
  mark_block self f f.body;
  f.has_return <- Array.exists nontail f.body;
  Array.iter nested f.body;
  Array.iter (fun p -> Option.iter nested p.default) f.params

and nested (e : expr) =
  match e.e with
  | Lambda g -> finish_tail None g
  | Fn_def ({ b = Local _; _ }, g) -> finish_tail None g
  | Fn_def _ -> ()
  | _ -> children nested e

let file ?(keep = [||]) ~file:path ~m ~lookup ~spaces (fn : func) =
  let env =
    { path; m; lookup; spaces; hoisted = Hashtbl.create 16; cells = Hashtbl.create 16; cell_list = [] }
  in
  Array.iter (fun text -> ignore (cell env text)) keep;
  let sc = { fn; kind = File; parent = None; vars = Hashtbl.create 16; names = []; caps = []; overlay = [] } in
  let hoisted = ref [] in
  Array.iter
    (fun (e : expr) ->
       match e.e with
       | Fn_def (n, f) ->
         if Hashtbl.mem env.hoisted n.text then error path e.pos (Messages.duplicate n.text);
         let k = cell env n.text in
         Hashtbl.add env.hoisted n.text k;
         hoisted := (k, f) :: !hoisted
       | _ -> ())
    fn.body;
  let top_hoisted (e : expr) = match e.e with Fn_def _ -> true | _ -> false in
  Array.iter (fun e -> if not (top_hoisted e) then assigned sc e) fn.body;
  Hashtbl.iter
    (fun text _ ->
       if Hashtbl.mem env.hoisted text then error path fn.fpos (Messages.assign_function text))
    sc.vars;
  let celled = ref [] in
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
  { cell_names = Array.of_list (List.rev env.cell_list); hoisted = Array.of_list (List.rev !hoisted) }
