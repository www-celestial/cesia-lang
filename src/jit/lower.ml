open Types
open Ast

(* Anything outside what the JIT takes: the version or the loop stays interpreted. *)
exception No

(* A guess that needs a value the frame doesn't hold yet: the loop can be lowered again later. *)
exception Unseen

(* A variable kept as a number for the whole run that an assignment can't keep so: the loop lowers again with it a value. *)
exception Respec of int

(* Statements of the branches of the region's ifs that don't lower, left to the interpreter: the loop lowers again with
   them out of what it looks at, as a variable they alone assign needs no register. *)
exception Cold of int list

(* A variable of a region kept as the values of a map it never makes (scalar replacement): read only as p.Name, assigned
   only by statements p = ps[i] of a list. Its values are in float registers; a map is made of them only when the run
   writes its variables back (allocation sinking), by [Engine]. *)
type sunk = { parts : int array; carrier : t  (* a map of its keys or a struct of its shape, no values *) }

(* The most cells of a small array of floats kept in slots of the float stack: fewer than 16, so that each operation on
   one costs one step, as the interpreter's. *)
let vmax = 15

(* The size of a body that gives such an array, inlined: a literal of three cells of arithmetic, as an equation's, is
   about 45. *)
let vbody = 120

(* A variable of a region, or a parameter of an inlined body, kept as a small array of floats in slots of the float
   stack, never made while the run lasts: its first slot in the frame's area of such arrays, its cells, its rows and
   columns; the value slot of a region's variable, which [Engine] fills from those slots after a run, or -1; [ro] for
   one the loop never assigns, which a run only reads, its array checked at entry and never made again. *)
type vecv = { slot : int; n : int; rows : int; cols : int; vslot : int; ro : bool }

(* A small array of floats being made: its cells, rows and columns; [cell j] makes cell [j], column by column, where it
   is asked for, and gives its operand; [at] its slots when it has some, else -1. *)
type vec = { vn : int; vr : int; vc : int; cell : int -> Ir.value; at : int }

(* A [for] lowered once: its counter, its bound, the block of its body, and whether it is innermost (no point, call or
   allocation in it), for the twin made in the fast copy of the loop around it. *)
type twin = { tc : int; th : int; tbody : int; tinner : bool }

(* Where an inlined body gives a small array of floats: its slots, from the first one given, and its shape. *)
type vout = { mutable out : int; mutable shape : int * int * int }

type st = {
  w : world;
  ver : version;
  f : func;
  index : int;  (* this function's number in the unit *)
  kinds : Ir.kind Vec.t;
  blocks : Ir.block Vec.t;
  mutable cur : int;
  regs : int array;  (* the register of each variable kept in one, or -1 *)
  arrays : int array;  (* the number of each variable that is a float array, or -1 *)
  arr : (int * bool * int * int) Vec.t;
      (* each array: its slot, whether written, its store: 0 floats, 1 values, and the indexes it takes past one *)
  hidden : Ir.var Vec.t;
  resumes : int Vec.t;
  mutable loops : int list;  (* where a break goes *)
  sites : (Pos.t * version * Bytes.t * bool) Vec.t;
      (* each site, the version whose code it is in, what is assigned there, and whether its frame keeps its variables in registers *)
  mutable live : Bytes.t;  (* with a debugger: what the last hook saw assigned, for the variables of a stop *)
  chains : (int * int * int) list Vec.t;  (* each site's inlined frames, as [Ir.func.chains] *)
  mutable inl : (int * int * int) list;  (* the inlined frames around the code being lowered, the innermost first *)
  mutable ret_to : (int * int) option;  (* in an inlined body: the register of its result and the block after it *)
  unit : unit_;
  mutable body : int;  (* the block after the step of the call, where a self tail call comes back *)
  region : bool;  (* a loop of the version, not the whole of it *)
  infos : (int * int * int * int) Vec.t;
      (* each loop: its node, the slots of its counter and bound or -1, its point after a step *)
  twins : (int, twin) Hashtbl.t;  (* each [for] lowered, for its twin *)
  mutable fast : (int, int * int * int) Hashtbl.t;
      (* in a loop's fast copy: each index proved inside, its array, its register and the cells after it *)
  mutable ncalls : int;  (* calls lowered so far *)
  mem : int array;
      (* shared with inlined bodies, the interpreter's view of the function's calls: the highest base of one from its frame,
         and the largest frame called; -1 when a callee has no interpreter's code yet *)
  ctx : ctx option;  (* a region's frame as it is now, whose values guide the guesses *)
  spec : bool array;  (* the variables of no type kept as a number for the whole run, as [Ir.func.numbers] *)
  sunk : sunk option array;
  inplace : bool array;  (* the lists whose maps of floats a write may change in place: no value variable holds one *)
  vecs : vecv option array;  (* the variables kept as small arrays of floats in slots *)
  flags : int array;
      (* of a variable kept as a number or a small array that a turn assigns before it reads it: an integer register set
         when the run assigns it, so that [Engine] writes back only what the run assigned; else -1 *)
  vret : vout option;  (* in an inlined body that gives a small array of floats: where *)
  dyn : dyn;  (* shared with inlined bodies *)
  fixed : bool array Lazy.t;  (* the parameters the function never assigns: their bounds hold in its whole body *)
  mutable resumable : bool;
      (* the statements lowered now are points the interpreter can go on from: those of the region's loop and of the
         branches of its ifs, not of a loop inside nor of an inlined body *)
  cold : int list;  (* the statements, inside the branches of the region's ifs, left to the interpreter *)
}

and dyn = {
  mutable bail : int option;
      (* the statement of the region's loop that a failed guard goes back to: only before anything of it shows but its
         assignments to variables, which the way back undoes *)
  mutable dirty : bool;  (* the statement assigned a variable already *)
  mutable callable : int option;
      (* the statement a call that wants a longer stack goes back to, its fuel as at its start: while nothing of it
         showed but steps *)
  restores : (int * int) list Vec.t;  (* of each statement: its variables' registers and their copies at its start *)
  keeps : (int * int * int) Vec.t;  (* of each statement: its fuel, as [Ir.Keep] *)
  mutable loose : bool;  (* a call that can't bail when it wants a longer stack *)
  mutable start : int * int;
      (* where the statement starts: its block and the instructions before it there, where its copies go when needed *)
  mutable vars : int list;  (* the registers of the variables the statement may assign *)
  mutable need : int ref option;  (* the words of allocation since the last [Reserve] *)
  consts : t Vec.t;
  mutable known : (int * int * int * int) list;
      (* in the block being built: a register of a map or struct already checked, its constant or -1 - its shape, and the
         register of its values *)
  mutable nums : (int * int * Ir.unbox * int) list;  (* in the block being built: a value's register, how, its number's *)
  mutable elems : (int * int * Ir.value * (int * int)) list;
      (* in the block being built: a cell of a list of values read, by its array and index, the map or struct there, of
         an F store checked, and the register of its doubles *)
  mutable lent : int list;  (* as [Ir.func.lent] *)
  mutable ticked : bool;  (* a step or a call since the statement's start: the fuel may differ from its start's *)
  mutable ranges : (int * (int * int)) list;  (* integer registers, each written once, and the bounds proved of them *)
  mutable inside : (int * int * int) list;
      (* in the block being built: an array and a register of an index checked inside it, which a later read or write of
         the same cell needs not check again *)
  points : int Vec.t;
      (* each statement a guard may go back to: -1 for a statement of the region's loop, whose number is its place, else
         the node of a statement in a branch of an if, numbered after them *)
  mutable copies : bool * bool;
      (* at this start of the statement, its copies of variables and its [Keep] are made: a loop's fast copy has a start
         of its own for each statement, whose numbers are those of the slow copy *)
  mutable colds : int list;  (* the statements found cold in this lowering *)
  mutable dead : bool;  (* the code being built follows a statement left to the interpreter: it never runs *)
  mutable starts : int list;  (* the block of each instruction put at a statement's start, the last first *)
  mutable vslots : int;  (* the slots of small arrays taken so far in the frame's area of them *)
  mutable cells : (int * int * t) list;  (* the variables of modules read as constants: module, cell, value *)
}

and unit_ = { versions : version Vec.t }

(* What a block may assign, or [Unknown] for a construct the walk doesn't follow: then nothing is taken as invariant. *)
exception Unknown

(* Each expression of [e], [e] first, of the forms a loop that lowers holds; [f] says whether to go inside. The statements
   [cold] names are left to the interpreter: what they hold isn't looked at. *)
let rec walk ?(cold = []) f (e : expr) =
  if (cold = [] || not (List.mem e.id cold)) && f e then begin
    let w = walk ~cold f in
    let ixs a = Array.iter (function Ix x -> w x | All -> ()) a in
    match e.e with
    | Field (x, _) | Neg x | Not x | Return { rvalue = Some x; _ } | Assign (_, x) -> w x
    | Bin (_, x, y) | And (x, y) | Or (x, y) | Range (x, y) -> w x; w y
    | If (c, y, n) -> w c; Array.iter w y; Array.iter w n
    | Index (x, a, _) -> w x; ixs a
    | Struct_lit { sfields; _ } -> Array.iter (fun (_, v) -> w v) sfields
    | Array_lit rows -> Array.iter (Array.iter w) rows
    | Interp parts -> Array.iter (function Hole x -> w x | Lit _ -> ()) parts
    | In_op (x, y) -> w x; w y
    | Question x -> w x
    | Call c -> w c.callee; Array.iter (fun (a : arg) -> w a.value) c.args
    | Set { path; value; _ } -> w value; Array.iter (fun (s : step) -> match s.sk with Sindex (a, _) -> ixs a | Sfield _ -> ()) path
    | For { iter; fbody; _ } -> w iter; Array.iter w fbody
    | While { cond; body; _ } -> w cond; Array.iter w body
    | _ -> ()
  end

(* With [sets] false, a variable written only through a path, as a cell of it, isn't counted. *)
let assigned ?(sets = true) ?cold acc e =
  let acc = ref acc in
  walk ?cold
    (fun (x : expr) ->
       (match x.e with
        | Assign ({ b = Local j; _ }, _) | For { var = { b = Local j; _ }; _ } -> acc := j :: !acc
        | Set { root = { b = Local j; _ }; _ } -> if sets then acc := j :: !acc
        | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ | Var _ | Break | Hook _ | Field _ | Struct_lit _ | Array_lit _ | While _ | If _
        | Return _ | Bin _ | And _ | Or _ | Range _ | Neg _ | Not _ | Index _ | Call _ | Interp _ | In_op _ | Question _
        | End_index ->
          ()
        | _ -> raise Unknown);
       true)
    e;
  !acc

(* The deepest nest of loops in [b]: 0 without a loop, 1 when every loop in it is innermost. *)
let rec nest (b : block) =
  let d = ref 0 in
  let inside body = d := max !d (1 + nest body); false in
  Array.iter (walk (fun (x : expr) -> match x.e with For { fbody; _ } -> inside fbody | While { body; _ } -> inside body | _ -> true)) b;
  !d

let math = [ "Sqrt", "sqrt"; "Exp", "exp"; "Log", "log"; "Sin", "sin"; "Cos", "cos"; "Tan", "tan"; "Asin", "asin";
             "Acos", "acos"; "Atan", "atan" ]

let reg st k = Vec.push st.kinds k
let block st = Vec.push st.blocks { Ir.ins = []; term = Return (Int 0) }

(* Something of the current statement shows: a guard can't send it back to the interpreter any more. *)
let shows st =
  st.dyn.bail <- None;
  st.dyn.callable <- None

(* Instructions are kept in reverse while a block is built. Steps forbid a guard after them, not a call, whose way back
   restores the fuel. *)
let emit st i =
  (* A cell whose index was checked in this block: read or written without a check. *)
  let i =
    match i with
    | Ir.Elem (r, a, Reg q, _) when List.mem (st.cur, a, q) st.dyn.inside -> Ir.Elem_at (r, a, q, 0)
    | Set_elem (a, Reg q, v, _) when List.mem (st.cur, a, q) st.dyn.inside -> Set_at (a, q, 0, v)
    | Elem (_, a, Reg q, _) | Set_elem (a, Reg q, _, _) -> st.dyn.inside <- (st.cur, a, q) :: st.dyn.inside; i
    | _ -> i
  in
  (match i with
   (* A step or a call shows nothing: a guard after it goes back with the fuel of the statement's start ([keep]). *)
   | Ir.Tick _ | Call _ | Burn -> st.dyn.ticked <- true
   | Set_elem (a, _, _, _) | Set_at (a, _, _, _) | Put (a, _, _, _) | Into (a, _, _, _, _, _, _, _) ->
     (* The cell may hold another map now. *)
     st.dyn.elems <- List.filter (fun (_, b, _, _) -> b <> a) st.dyn.elems;
     shows st
   | Incr r | Bump (r, _) ->
     st.dyn.elems <- List.filter (fun (_, _, i, _) -> i <> Ir.Reg r) st.dyn.elems;
     st.dyn.inside <- List.filter (fun (_, _, q) -> q <> r) st.dyn.inside;
     shows st
   | Move (r, x) ->
     let d = st.dyn in
     d.known <- List.filter (fun (_, m, _, _) -> m <> r) d.known;
     d.nums <- List.filter (fun (_, v, _, _) -> v <> r) d.nums;
     d.elems <- List.filter (fun (_, _, i, _) -> i <> Ir.Reg r) d.elems;
     d.inside <- List.filter (fun (_, _, q) -> q <> r) d.inside;
     (* What the source holds, the destination holds too. *)
     (match x with
      | Reg q ->
        d.known <- List.concat_map (fun ((b, m, c, a) as e) -> if m = q then [ e; (b, r, c, a) ] else [ e ]) d.known;
        d.nums <- List.concat_map (fun ((b, v, h, n) as e) -> if v = q then [ e; (b, r, h, n) ] else [ e ]) d.nums
      | _ -> ())
   | _ -> ());
  let b = Vec.get st.blocks st.cur in
  b.ins <- i :: b.ins

let close st t = (Vec.get st.blocks st.cur).term <- t

(* What is known in block [b]: then known in block [l] too, which [b] dominates. *)
let facts st b =
  ( List.filter (fun (x, _, _, _) -> x = b) st.dyn.known, List.filter (fun (x, _, _, _) -> x = b) st.dyn.nums,
    List.filter (fun (x, _, _, _) -> x = b) st.dyn.elems )

let carry st (k, n, c) l =
  st.dyn.known <- List.map (fun (_, m, c, a) -> (l, m, c, a)) k @ st.dyn.known;
  st.dyn.nums <- List.map (fun (_, v, h, r) -> (l, v, h, r)) n @ st.dyn.nums;
  st.dyn.elems <- List.map (fun (_, a, i, x) -> (l, a, i, x)) c @ st.dyn.elems

(* After both branches of an [if], at [join]: what each knew at its end. *)
let meet st (k1, n1, c1) (k2, n2, c2) join =
  let k = List.filter (fun (_, m, c, a) -> List.exists (fun (_, m', c', a') -> m = m' && c = c' && a = a') k2) k1 in
  let n = List.filter (fun (_, v, h, r) -> List.exists (fun (_, v', h', r') -> v = v' && h = h' && r = r') n2) n1 in
  let c = List.filter (fun (_, a, i, x) -> List.exists (fun (_, a', i', x') -> a = a' && i = i' && x = x') c2) c1 in
  carry st (k, n, c) join

let goto st l =
  close st (Jump l);
  st.cur <- l

(* With a debugger, the outermost frame of a unit writes its variables back on an error; an inlined or called one keeps
   them in registers, and a stop shows none of its own. *)
let site st pos =
  Vec.add_last st.chains st.inl;
  Vec.push st.sites (pos, st.ver, (if st.inl = [] && st.index = 0 then st.live else Bytes.empty), st.inl <> [] || st.index > 0)

let point st l = Vec.push st.resumes l

(* A tick can leave the run only in no loop of the function, or as the tick of a loop in no other. *)
let outer st = st.loops = []

(* A tick, then on to [l]; the run comes back at [resume], [l] unless a block outside the loop says the same. *)
let tick ?resume st l =
  let p = point st (Option.value resume ~default:l) in
  emit st (Ir.Tick (p, outer st, -1));
  goto st l;
  p

let kind_of = function TI -> Ir.Kint | TF -> Ir.Kfloat | _ -> raise No
let ty st (e : expr) = st.ver.tn.(e.id)

let plain st i =
  (st.f.cell_of = [||] || st.f.cell_of.(i) < 0) && not st.f.maybe_undef.(i)

let var st i =
  if not (plain st i) || st.regs.(i) < 0 then raise No;
  st.regs.(i)

let array_of st (e : expr) =
  match e.e with
  | Var { b = Local i; _ } when st.arrays.(i) >= 0 -> st.arrays.(i)
  | _ -> raise No

(* The kind of the cells of array [a]: doubles of a store of floats, integers of a store of integers (a list of whole
   numbers), or values. *)
let cells_of st a = match Vec.get st.arr a with _, _, 0, _ -> Ir.Kfloat | _, _, 2, _ -> Kint | _ -> Kval

(* An instruction at the start of the current statement, put there once it is known to be needed. *)
let at_start st i =
  let b, n = st.dyn.start in
  st.dyn.starts <- b :: st.dyn.starts;
  let blk = Vec.get st.blocks b in
  let rec split k l = if k = 0 then [], l else match l with x :: r -> let a, c = split (k - 1) r in x :: a, c | [] -> [], [] in
  let later, earlier = split (List.length blk.ins - n) blk.ins in
  blk.ins <- later @ (i :: earlier)

(* The fuel, the steps spent and the quantum at the start of statement [k], kept there once a way back needs them. *)
let keep st k =
  let restored, kept = st.dyn.copies in
  if Vec.get st.dyn.keeps k = (-1, -1, -1) then begin
    let f = reg st Kint and sp = reg st Kint and q = reg st Kint in
    Vec.set st.dyn.keeps k (f, sp, q)
  end;
  if not kept then begin
    let f, sp, q = Vec.get st.dyn.keeps k in
    at_start st (Ir.Keep (f, sp, q));
    st.dyn.copies <- (restored, true)
  end

(* The statement a failed guard goes back to, putting back the variables it assigned so far and the fuel it spent, or
   no lowering. Their copies at its start are made at the first such guard. *)
let bail st =
  match st.dyn.bail with
  (* The test of the region's while, made again by the interpreter: no step may come before. *)
  | Some k when k < 0 -> if st.dyn.ticked then raise No else k
  | Some k ->
    let refuel = if st.dyn.ticked then (keep st k; Ir.refuel) else 0 in
    if st.dyn.dirty then begin
      if Vec.get st.dyn.restores k = [] && st.dyn.vars <> [] then
        Vec.set st.dyn.restores k (List.map (fun r -> r, reg st (Vec.get st.kinds r)) st.dyn.vars);
      let restored, kept = st.dyn.copies in
      if not restored then begin
        List.iter (fun (r, c) -> at_start st (Ir.Move (c, Reg r))) (Vec.get st.dyn.restores k);
        st.dyn.copies <- (true, kept)
      end;
      refuel + Ir.restored + k
    end
    else refuel + k
  | None -> raise No

(* The number in a value, checked once in a block. *)
let unbox st v how =
  let k = if how = Ir.Only_int then Ir.Kint else Kfloat in
  match v with
  | Ir.Reg q when List.exists (fun (b, x, h, _) -> b = st.cur && x = q && h = how) st.dyn.nums ->
    let _, _, _, r = List.find (fun (b, x, h, _) -> b = st.cur && x = q && h = how) st.dyn.nums in
    Ir.Reg r, k
  | _ ->
    let r = reg st k in
    emit st (Unbox (r, v, how, bail st));
    (match v with Reg q -> st.dyn.nums <- (st.cur, q, how, r) :: st.dyn.nums | _ -> ());
    Reg r, k

let to_float st (v, k) =
  match k, v with
  | Ir.Kfloat, _ -> v
  | Kint, Ir.Int n -> Float (float_of_int n)
  | Kint, _ ->
    let r = reg st Kfloat in
    emit st (Float_of (r, v));
    Reg r
  | Kval, _ -> fst (unbox st v Number)

let fresh st k f =
  let r = reg st k in
  emit st (f r);
  Ir.Reg r, k

(* The bounds proved of an integer operand, small ones only, so that no sum of two overflows; a bound at small is none:
   (2, small) is any integer from 2 up. *)
let small = 1 lsl 60
let range st = function
  | Ir.Int n when n > - small && n < small -> Some (n, n)
  | Reg q -> List.assoc_opt q st.dyn.ranges
  | _ -> None

(* The bounds of a sum, or None when it may overflow: down only when both may be far below 0, up likewise. *)
let sum (a, b) (c, d) =
  let clamp x = max (- small) (min small x) in
  if ((a > - small && c > - small) || a >= 0 || c >= 0) && ((b < small && d < small) || b <= 0 || d <= 0) then
    Some ((if a = - small || c = - small then - small else clamp (a + c)), if b = small || d = small then small else clamp (b + d))
  else None

(* The bounds a condition proves of the integer parameters it compares with a constant, when it holds ([truth]) or not:
   from the else branch of [if n < 2] on, n - 1 can't overflow. A parameter the function assigns proves nothing. *)
let rec bounds st (c : expr) truth =
  match c.e with
  | Not a -> bounds st a (not truth)
  | And (a, b) when truth -> bounds st a true @ bounds st b true
  | Or (a, b) when not truth -> bounds st a false @ bounds st b false
  | Bin (((Lt | Le | Gt | Ge | Eq) as op), x, y) ->
    let fixed i = i < Array.length st.f.params && st.regs.(i) >= 0 && Vec.get st.kinds st.regs.(i) = Ir.Kint && (Lazy.force st.fixed).(i) in
    let one op i k =
      let r = st.regs.(i) in
      let lo, hi = Option.value (List.assoc_opt r st.dyn.ranges) ~default:(- small, small) in
      match op, truth with
      | Lt, true | Ge, false -> [ r, (lo, min hi (k - 1)) ]
      | Le, true | Gt, false -> [ r, (lo, min hi k) ]
      | Gt, true | Le, false -> [ r, (max lo (k + 1), hi) ]
      | Ge, true | Lt, false -> [ r, (max lo k, hi) ]
      | Eq, true -> [ r, (max lo k, min hi k) ]
      | _ -> []
    in
    (match x.e, y.e with
     | Var { b = Local i; _ }, Lint k when fixed i && abs k < small - 1 -> one op i k
     | Lint k, Var { b = Local i; _ } when fixed i && abs k < small - 1 ->
       one (match op with Lt -> Gt | Le -> Ge | Gt -> Lt | Ge -> Le | o -> o) i k
     | _ -> [])
  | _ -> []

(* Lowers [f] with the bounds of each branch of the test [c] added to what is proved. *)
let assume st c truth f =
  let saved = st.dyn.ranges in
  st.dyn.ranges <- bounds st c truth @ saved;
  f ();
  st.dyn.ranges <- saved

(* The parameters [body] never assigns, nor a self tail call. *)
let fixed_params (f : func) =
  lazy
    (let all = try Some (Array.fold_left (assigned ~sets:true) [] (Lazy.force f.body)) with Unknown -> None in
     Array.init (Array.length f.params) (fun i -> (not f.has_self_tail) && match all with Some l -> not (List.mem i l) | None -> false))

let proves st (r, _) = function
  | Some bounds -> (match r with Ir.Reg q -> st.dyn.ranges <- (q, bounds) :: st.dyn.ranges | _ -> ())
  | None -> ()

(* What the frame holds now for a variable of the region, a field of it or a cell of one of its arrays: the guess that
   guards then check. *)
let rec observe st (e : expr) =
  match st.ctx, e.e with
  | _, Lmissing -> Some Missing
  | _, Lbool b -> Some (if b then True else False)
  | Some ctx, Var { b = Local i; _ } when st.inl = [] && st.ver.tv.(i) == TA ->
    (match ctx.v.(ctx.b + st.ver.map.(i)) with Undef -> None | v -> Some v)
  | Some _, Field (b, name) ->
    (match observe st b with
     | Some (Dict { keys = { deep = Flat; _ } as keys; vals; _ }) ->
       let key = Text name in
       let j = Trie.index keys (Trie.nvals vals) (Trie.hash key) key in
       if j >= 0 then Some (Trie.vget vals j) else None
     | Some (Struct r) ->
       let j = Value.field_index r.shape name in
       if j >= 0 then Some (Trie.vget r.fields j) else None
     | _ -> None)
  | Some ctx, Index ({ e = Var { b = Local a; _ }; _ }, ixs, false) when st.inl = [] ->
    let num = function
      | Ix { e = Lint n; _ } -> Some n
      | Ix { e = Var { b = Local j; _ }; _ } when st.ver.tv.(j) == TI -> Some ctx.i.(ctx.b + st.ver.map.(j))
      | _ -> None
    in
    let ns = Array.map num ixs in
    (match ctx.v.(ctx.b + st.ver.map.(a)) with
     | _ when Array.exists Option.is_none ns -> None
     | Array x ->
       (* The cell, column by column, of indexes one per dimension, or one alone. *)
       let sizes = if Array.length ns = 1 then [| x.rows * x.cols |] else Arrays.sizes x in
       if Array.length sizes <> Array.length ns then None
       else begin
         let rec go d off stride =
           if d = Array.length ns then Some (Value.elt x off)
           else
             let k = Option.get ns.(d) in
             if k >= 1 && k <= sizes.(d) then go (d + 1) (off + ((k - 1) * stride)) (stride * sizes.(d)) else None
         in
         go 0 0 1
       end
     | _ -> None)
  | _ -> None

(* A guess without its value: later, when a frame may hold it; never, without one. *)
let unseen st = if st.ctx = None then raise No else raise Unseen

(* A constant whose first field native code reads, in a value slot after the frame: one per value of that field. *)
let const st (v : t) =
  let same a b =
    match a, b with
    | Dict { keys = x; _ }, Dict { keys = y; _ } -> x == y
    | Struct { shape = x; _ }, Struct { shape = y; _ } -> x == y
    | Fun { proto = x; _ }, Fun { proto = y; _ } -> x == y
    | _ -> false
  in
  let cs = st.dyn.consts in
  let rec find j = if j = Vec.length cs then (Vec.add_last cs v; j) else if same (Vec.get cs j) v then j else find (j + 1) in
  find 0

(* Room for an allocation, in the words reserved at the last [Reserve]. *)
let alloc st words =
  match st.dyn.need with
  | Some r ->
    r := !r + words;
    if !r > 1024 then raise No
  | None -> raise No

(* A number as a value: an Int or a Float, made in reserved room. *)
let box st (x, k) =
  match k with
  | Ir.Kval -> x
  | Kint | Kfloat ->
    alloc st (if k = Kint then 2 else 4);
    let r = reg st Kval in
    emit st (Box (r, x));
    (* What it holds is known in this block. *)
    (match x with
     | Reg q when k = Kfloat -> st.dyn.nums <- (st.cur, r, Number, q) :: (st.cur, r, Only_float, q) :: st.dyn.nums
     | Reg q -> st.dyn.nums <- (st.cur, r, Only_int, q) :: st.dyn.nums
     | _ -> ());
    Reg r

(* A value that arithmetic takes: guessed from what the frame holds, a Float or an Int, and checked. *)
let guess st (e : expr) (x, k) =
  match k with
  | Ir.Kval ->
    (match observe st e with
     | Some (Float _) -> unbox st x Only_float
     | Some (Int _) -> unbox st x Only_int
     | Some _ -> raise No
     | None -> unseen st)
  | _ -> x, k

(* The operands of arithmetic or a comparison: a value beside a float is a number made a float, as the interpreter's
   arithmetic does; otherwise a guess. *)
let numbers st a b x y =
  match snd x, snd y with
  | Ir.Kval, Ir.Kfloat -> (to_float st x, Ir.Kfloat), y
  | Kfloat, Kval -> x, (to_float st y, Kfloat)
  | Kval, _ | _, Kval ->
    let x = guess st a x in
    x, guess st b y
  | _ -> x, y

(* The function of the unit for a version, lowered later. The first is the unit's entry, a region or the outermost frame
   of its version: a call of that version goes to a nested copy of its own. *)
let callee st (v : version) =
  let vs = st.unit.versions in
  let rec find i = if i = Vec.length vs then (Vec.add_last vs v; i) else if Vec.get vs i == v then i else find (i + 1) in
  find 1

(* The outermost frame of a version calls its own nested copy instead of holding itself inlined: it runs once per call
   from the interpreter, and its code then costs MIR half the time to make. *)
let own st (v : version) = st.index = 0 && v == Vec.get st.unit.versions 0

let rec expr st (e : expr) : Ir.value * Ir.kind =
  match e.e with
  | Lint n -> Int n, Kint
  | Lfloat x when Float.is_finite x -> Float x, Kfloat
  (* Words of [Types.t] that are no block. *)
  | Lmissing -> Word 1, Kval
  | Lbool b -> Word (if b then 5 else 7), Kval
  | Var { b = Local i; _ } -> Reg (var st i), Vec.get st.kinds (var st i)
  | Var { b = Cell { m; k; stable = true }; _ } ->
    (match st.w.modules.(m).cells.(k) with
     | Int n -> Int n, Kint
     | Float x when Float.is_finite x -> Float x, Kfloat
     | _ -> raise No)
  (* A variable of a module, as eps = 2.2e-16 at the top of a file: native code never assigns one, and only the code of
     the file's top does, so its number now is a constant of the unit, which [Engine] checks before each run. *)
  | Var { b = Cell { m; k; stable = false }; _ } ->
    let v = st.w.modules.(m).cells.(k) in
    let c = match v with Int n -> (Ir.Int n, Ir.Kint) | Float x when Float.is_finite x -> Float x, Kfloat | _ -> raise No in
    if not (List.exists (fun (m', k', _) -> m' = m && k' = k) st.dyn.cells) then st.dyn.cells <- (m, k, v) :: st.dyn.cells;
    c
  | Bin (((Add | Sub | Mul) as op), a, b) ->
    let x = expr st a in
    let y = expr st b in
    let x, y = numbers st a b x y in
    (match snd x, snd y with
     | Kint, Kint ->
       let op = match op with Add -> Ir.Add | Sub -> Sub | _ -> Mul in
       (* Bounds proved of both operands that keep the result far from overflow: no check (range analysis). *)
       let proved =
         match op, range st (fst x), range st (fst y) with
         | Ir.Add, Some p, Some q -> sum p q
         | Sub, Some p, Some (c, d) -> sum p (- d, - c)
         | _ -> None
       in
       let r = fresh st Kint (fun r -> Op (op, r, fst x, fst y, if proved = None then site st e.pos else -1)) in
       proves st r proved;
       r
     | _ ->
       let op = match op with Add -> Ir.Fadd | Sub -> Fsub | _ -> Fmul in
       let x = to_float st x in
       let y = to_float st y in
       fresh st Kfloat (fun r -> Op (op, r, x, y, -1)))
  (* A division is always a float, of numbers; a power only when a float is known, as of integers it is an integer. *)
  | Bin (((Div | Pow) as op), a, b) when op = Div || ty st e == TF || ty st a == TF || ty st b == TF ->
    let x = to_float st (expr st a) in
    let y = to_float st (expr st b) in
    fresh st Kfloat (fun r -> Op ((if op = Div then Fdiv else Fpow), r, x, y, -1))
  | Neg a ->
    (match guess st a (expr st a) with
     | x, Kint -> fresh st Kint (fun r -> Neg (r, x, site st e.pos))
     | x, Kfloat -> fresh st Kfloat (fun r -> Fneg (r, x))
     | _, Kval -> raise No)
  | If (c, yes, no) when ty st e == TI || ty st e == TF ->
    let k = kind_of (ty st e) in
    let r = reg st k and y = block st and n = block st and join = block st in
    let b0 = st.cur in
    cond st c y n;
    let base = facts st b0 in
    carry st base y;
    st.cur <- y;
    assume st c true (fun () -> emit st (Move (r, convert st k (value_block st yes))));
    let end_yes = facts st st.cur in
    goto st join;
    carry st base n;
    st.cur <- n;
    assume st c false (fun () -> emit st (Move (r, convert st k (value_block st no))));
    let end_no = facts st st.cur in
    goto st join;
    meet st end_yes end_no join;
    Reg r, k
  (* An if of no type, as one of numbers of the region: of the kind both branches' values have. A value beside a number
     is guessed as that number, checked at the end of its branch, as arithmetic does: a variable of no type holds a
     value, as err in facold = if err > 1.0e-4 err else 1.0e-4 end. *)
  | If (c, yes, no) when ty st e == TA && Array.length yes > 0 && Array.length no > 0 ->
    let y = block st and n = block st and join = block st in
    let b0 = st.cur in
    cond st c y n;
    let base = facts st b0 in
    carry st base y;
    st.cur <- y;
    let vy = ref (Ir.Int 0, Ir.Kval) and vn = ref (Ir.Int 0, Ir.Kval) in
    assume st c true (fun () -> vy := value_block st yes);
    let end_y = st.cur in
    carry st base n;
    st.cur <- n;
    assume st c false (fun () -> vn := value_block st no);
    let end_n = st.cur in
    let k = match snd !vy, snd !vn with a, b when a = b -> a | Kval, b -> b | a, Kval -> a | _ -> raise No in
    let r = reg st k in
    let finish at (b : block) v =
      st.cur <- at;
      let x =
        match v with
        | x, k' when k' = k -> x
        | v -> (match guess st b.(Array.length b - 1) v with x, k' when k' = k -> x | _ -> raise No)
      in
      emit st (Move (r, x));
      let known = facts st st.cur in
      goto st join;
      known
    in
    let end_yes = finish end_y yes !vy in
    let end_no = finish end_n no !vn in
    meet st end_yes end_no join;
    Reg r, k
  | Index ({ e = Var { b = Local i; _ }; _ }, [| Ix ix |], false) when st.vecs.(i) <> None ->
    let v = Option.get st.vecs.(i) in
    (match guess st ix (expr st ix) with
     | Int k, Kint when k >= 1 && k <= v.n -> fresh st Kfloat (fun r -> Vget (r, v.slot + k - 1))
     | x, Kint -> fresh st Kfloat (fun r -> Vat (r, v.slot, v.n, x, site st e.pos, v.rows, v.cols))
     | _ -> raise No)
  | Index (b, _, false) when Hashtbl.mem st.fast e.id ->
    let a, ix, k = Hashtbl.find st.fast e.id in
    ignore (array_of st b);
    fresh st (cells_of st a) (fun r -> Elem_at (r, a, ix, k))
  | Index (b, [| Ix i |], false) ->
    let a = array_of st b in
    (match guess st i (expr st i), cells_of st a with
     | (x, Kint), Kval -> fresh st Kval (fun r -> Get (r, a, x, site st e.pos))
     | (x, Kint), k -> fresh st k (fun r -> Elem (r, a, x, site st e.pos))
     | _ -> raise No)
  | Index (b, ixs, false) when Array.length ixs >= 2 ->
    let a = array_of st b in
    let q = cell st a (indexes st a ixs) e.pos false in
    (match cells_of st a with
     | Kval -> fresh st Kval (fun r -> Get (r, a, Reg q, site st e.pos))
     | k -> fresh st k (fun r -> Elem_at (r, a, q, 0)))
  | Field ({ e = Var { b = Local i; _ }; _ }, name) when sunk_map st i ->
    let s = Option.get st.sunk.(i) in
    let j =
      match s.carrier with
      | Dict { keys; _ } -> Trie.index keys (Array.length keys.ks) (Trie.hash (Text name)) (Text name)
      | Struct { shape; _ } when visible st shape name -> Value.field_index shape name
      | _ -> -1
    in
    if j < 0 then raise No;
    Reg s.parts.(j), Kfloat
  | Field (b, name) ->
    let v = (match expr st b with v, Kval -> v | _ -> raise No) in
    (match observe st b with
     | Some (Dict { keys = { deep = Flat; _ } as keys; vals; _ }) ->
       let key = Text name in
       let j = Trie.index keys (Trie.nvals vals) (Trie.hash key) key in
       if j < 0 then unseen st;
       let c = const st (Dict { keys; vals = Trie.no_vals; d_owned = false }) in
       (* The values' store as the frame holds it: floats, read as doubles, or values. *)
       let f = (match vals with F _ -> 0 | _ -> 1) in
       let a = checked st v ((2 * c) + f) (fun r -> Ir.Vals (r, v, c, f, bail st)) in
       (* Keys that grow in place can be held by a map of fewer values. *)
       let k = if Trie.is_whole keys then -1 else bail st in
       fresh st (if f = 0 then Kfloat else Kval) (fun r -> Load (r, a, j, k))
     | Some (Struct { shape; fields; _ }) ->
       let j = Value.field_index shape name in
       if j < 0 || not (visible st shape name) then raise No;
       let f = (match fields with F _ -> 0 | _ -> 1) in
       let a = checked st v (-1 - ((2 * shape.sid) + f)) (fun r -> Ir.Fields (r, v, shape.sid, f, bail st)) in
       fresh st (if f = 0 then Kfloat else Kval) (fun r -> Load (r, a, j, -1))
     | Some _ -> raise No
     | None -> unseen st)
  | Struct_lit _ -> record st e
  | Bin ((Lt | Le | Gt | Ge | Eq | Ne), _, _) | And _ | Or _ | Not _ -> truth st e, Kval
  | Call call when kind_test st call <> None -> truth st e, Kval
  | Call call -> call_expr st e call
  | _ -> raise No

(* A variable kept as a map or struct that the run never makes. *)
and sunk_map st i = st.inl = [] && st.sunk.(i) <> None

(* A field the code may read: not a small field of a struct of another package, the interpreter's error. *)
and visible st (shape : shape) name =
  not (shape.sm >= 0 && shape.sname <> None && (not (Lexer.is_public name)) && st.w.modules.(st.ver.owner.pm).host <> shape.sm)

(* A literal's constant, its keys or shape, the same as the interpreter's so that both make the same maps, and its
   values: doubles when a map's are all floats, kept in its F store as the interpreter's literal does, else values. *)
and literal st sname sfields =
  let names = Array.map fst sfields in
  let n = Array.length names in
  if n = 0 || n > Trie.width || List.length (List.sort_uniq String.compare (Array.to_list names)) < n then raise No;
  let carrier =
    match sname with
    | None -> Dict { keys = Compile.map_keys names; vals = Trie.no_vals; d_owned = false }
    | Some _ ->
      let shape = Value.shape_of st.w ?sname ~m:st.w.modules.(st.ver.owner.pm).host names in
      Struct { shape; fields = Trie.no_vals; r_owned = false }
  in
  let vals, floats = values st (Array.map snd sfields) in
  const st carrier, vals, floats

(* The values of a new map or struct: doubles when all are floats, kept in an F store as the interpreter does, else
   values. *)
and values st es =
  (* A value that holds a float now is unboxed, with a guard, where one can bail: the interpreter's literal of floats
     makes an F store, and so must this one, or its maps' readers guess wrong. *)
  let xs =
    Array.map
      (fun (e : expr) ->
         match expr st e with
         | x, Ir.Kval when st.dyn.bail <> None && (match observe st e with Some (Float _) -> true | _ -> false) -> unbox st x Only_float
         | x -> x)
      es
  in
  let floats = Array.for_all (fun (_, k) -> k = Ir.Kfloat) xs in
  Array.mapi (fun j x -> if floats then fst x else stored_x st es.(j) x) xs, floats

(* The values of a map or the fields of a struct, checked once in a block. *)
and checked st v c make =
  match v with
  | Ir.Reg m when List.exists (fun (b, x, y, _) -> b = st.cur && x = m && y = c) st.dyn.known ->
    let _, _, _, a = List.find (fun (b, x, y, _) -> b = st.cur && x = m && y = c) st.dyn.known in
    a
  | _ ->
    let a = reg st Kval in
    emit st (make a);
    (match v with Reg m -> st.dyn.known <- (st.cur, m, c, a) :: st.dyn.known | _ -> ());
    a

(* A value about to be stored elsewhere, as the interpreter's [ce] gives it: one read from a variable, a field or a cell is
   shared; a number is boxed. *)
and stored st (e : expr) = stored_x st e (expr st e)

and stored_x st (e : expr) x =
  match x with
  | x, Kval ->
    (match e.e with Var _ | Index _ | Field _ when not (number st x) -> emit st (Share x) | _ -> ());
    x
  | x -> box st x

(* A value known in this block to be an Int or a Float, which no mark of sharing concerns. *)
and number st = function
  | Ir.Reg q -> List.exists (fun (b, v, _, _) -> b = st.cur && v = q) st.dyn.nums
  | _ -> false

(* While nothing of the statement showed but steps, a call that wants a longer stack bails: the interpreter makes it,
   with the fuel of the statement's start, kept there. Else such a call stops the run, which then must write nothing. *)
and back st =
  match st.dyn.callable with
  | Some k when not st.dyn.dirty ->
    (* Before any step or call of the statement, the fuel is still its start's: nothing to keep. *)
    if st.dyn.ticked then (keep st k; Ir.refuel + k) else k
  | _ ->
    st.dyn.loose <- true;
    -1

(* A small callee without a loop is lowered in place, one level deep: its frame is virtual, written only when an error or
   a limit unwinds through it, so traces and the limit of depth stay the interpreter's. *)
and inlinable ?(any = false) ?(most = 40) (v : version) =
  let f = v.owner.func in
  let rec size (e : expr) =
    let blk b = Array.fold_left (fun n x -> n + size x) 0 b in
    1
    + (match e.e with
       | For _ | While _ -> 1000
       | If (c, y, n) -> size c + blk y + blk n
       | Bin (_, x, y) | And (x, y) | Or (x, y) -> size x + size y
       | Neg x | Not x | Assign (_, x) | Return { rvalue = Some x; _ } -> size x
       | Call c -> Array.fold_left (fun n (a : arg) -> n + size a.value) (size c.callee) c.args
       | Index (x, _, _) -> size x + 2
       | Array_lit rows -> Array.fold_left (fun n row -> Array.fold_left (fun n x -> n + size x) n row) 0 rows
       | _ -> 1)
  in
  (any || v.ret == TI || v.ret == TF) && v.state = 2 && Array.length f.captures = 0 && (not f.has_self_tail)
  && blk_size size (Lazy.force f.body) <= most

and blk_size size b = Array.fold_left (fun n x -> n + size x) 0 b

(* A call to [v] from the code of [st.ver]: where the interpreter would put its frame, and how much that frame takes. A
   version the interpreter hasn't compiled yet has no size: the limit of memory then counts native frames only. *)
and note st (v : version) =
  if v.size = 0 || st.mem.(0) < 0 then (st.mem.(0) <- -1; st.mem.(1) <- -1)
  else begin
    st.mem.(0) <- max st.mem.(0) st.ver.call_off;
    st.mem.(1) <- max st.mem.(1) v.size
  end

and inline st (e : expr) (v : version) args = inline_args st e v (Array.map (fun x -> `S x) args) None

(* [inline] with arguments that may be small arrays in slots, and, given [vout], a body that gives one. *)
and inline_args st (e : expr) (v : version) args vout =
  let callsite = site st e.pos in
  let base = match st.inl with [] -> -1 | (vb, _, _) :: _ -> vb in
  let vb = reg st Kint in
  emit st (Frame (vb, base));
  emit st (Enter (vb, base, callsite, back st));
  let f = v.owner.func in
  (* A result of no kind takes the kind of the first value the body gives. *)
  let res = if vout = None && (v.ret == TI || v.ret == TF) then reg st (kind_of v.ret) else -1 and cont = block st in
  let dead = st.dyn.dead in
  let child =
    { st with ver = v; f; regs = Array.make f.nvars (-1); arrays = Array.make f.nvars (-1); spec = Array.make f.nvars false; sunk = Array.make f.nvars None; inplace = Array.make f.nvars false; loops = [];
              inl = (vb, base, callsite) :: st.inl; ret_to = Some (res, cont); body = 0; region = false;
              fast = Hashtbl.create 1; fixed = fixed_params f; resumable = false; vecs = Array.make f.nvars None; vret = vout; flags = Array.make f.nvars (-1) }
  in
  for i = 0 to f.nvars - 1 do
    match v.tv.(i) with TI | TF -> child.regs.(i) <- reg st (kind_of v.tv.(i)) | _ -> ()
  done;
  Array.iteri
    (fun j a ->
       match a with
       | `S (x, xk) ->
         (* A value for a parameter of a number, as the version the interpreter chose saw it. *)
         let x, xk =
           match v.tv.(j), xk with
           | TI, Ir.Kval -> unbox st x Only_int
           | TF, Kval -> unbox st x Only_float
           | _ -> x, xk
         in
         (* A parameter of no type holds the argument as it comes. *)
         if child.regs.(j) < 0 && v.tv.(j) == TA && plain child j then child.regs.(j) <- reg st xk;
         let r = child.regs.(j) in
         if r < 0 then raise No;
         emit child (Move (r, convert child (Vec.get st.kinds r) (x, xk)))
       | `V (k, (x : vec)) ->
         if (v.tv.(j) != TA && v.tv.(j) != TFA) || not (plain child j) then raise No;
         (* The body reads the caller's slots, or a copy of them when it assigns its parameter. *)
         let k =
           if (Lazy.force child.fixed).(j) then k
           else begin
             let c = take st x.vn in
             for i = 0 to x.vn - 1 do emit st (Vset (c + i, fst (fresh st Kfloat (fun r -> Vget (r, k + i))))) done;
             c
           end
         in
         child.vecs.(j) <- Some { slot = k; n = x.vn; rows = x.vr; cols = x.vc; vslot = -1; ro = false })
    args;
  (* The callee's step, as its frame's entry counts one. *)
  emit child (Ir.Tick (-1, false, site child e.pos));
  tail_block child (Lazy.force f.body);
  st.cur <- cont;
  st.ncalls <- child.ncalls + 1;
  (* No way of the body comes back, each left to the interpreter: what follows never runs. *)
  st.dyn.dead <- dead || not (Array.exists (fun (b : Ir.block) -> b.term = Jump cont) (Vec.to_array st.blocks));
  match child.ret_to with
  | Some (r, _) when r >= 0 -> Ir.Reg r, Vec.get st.kinds r
  | _ -> Ir.Float 0., Kfloat

(* Integer indexes, one per dimension of array [a], which then takes that many: its sizes are read at each entry. *)
and indexes st a (ixs : index array) =
  let slot, written, store, nd = Vec.get st.arr a in
  let n = Array.length ixs in
  if n > Ir.max_ixs || (nd <> 0 && nd <> n) then raise No;
  Vec.set st.arr a (slot, written, store, n);
  Array.map (function Ix i -> (match guess st i (expr st i) with x, Kint -> x | _ -> raise No) | All -> raise No) ixs

(* The register of the cell at those indexes, checked inside, from 1 and doubled as [Elem_at] takes it. *)
and cell st a xs pos write =
  match fresh st Kint (fun r -> Offset (r, a, xs, site st pos, write)) with
  | Reg q, _ -> q
  | _ -> raise No

and convert st k (v, vk) = if k = vk then v else if k = Ir.Kfloat then to_float st (v, vk) else raise No

(* A value written into a cell of array [a] of numbers: a double for floats; for integers, an integer alone, as any other
   value turns the interpreter's store into one of values, which native code doesn't make. *)
and cell_value st a value =
  match cells_of st a with
  | Ir.Kint ->
    (match expr st value with
     | x, Kint -> x
     | x, Kval when st.dyn.bail <> None -> fst (unbox st x Only_int)
     | _ -> raise No)
  | _ -> to_float st (expr st value)

and value_block st (b : block) =
  let n = Array.length b in
  if n = 0 then raise No;
  for j = 0 to n - 2 do stmt st b.(j) done;
  expr st b.(n - 1)

and args_of (call : call) n =
  if Array.length call.args <> n || Array.exists (fun (a : arg) -> a.aname <> None) call.args then raise No;
  Array.map (fun (a : arg) -> a.value) call.args

and call_expr st e (call : call) =
  (* A self tail call loops in [tail]; anywhere else the interpreter keeps it. *)
  if call.self_tail then raise No;
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; _ } ->
    (match st.w.modules.(m).cells.(k) with
     | Native { nname = ("Div" | "Mod") as name; _ } ->
       let a = args_of call 2 in
       let x = expr st a.(0) and y = expr st a.(1) in
       if snd x <> Kint || snd y <> Kint then raise No;
       let r = fresh st Kint (fun r -> Op ((if name = "Div" then Div else Mod), r, fst x, fst y, site st e.pos)) in
       (* The floor modulo by a positive constant d is in 0..d - 1. *)
       proves st r (match name, y with "Mod", (Ir.Int d, _) when d > 0 -> Some (0, d - 1) | _ -> None);
       r
     | Native { nname; f1 = Some _; _ } when List.mem_assoc nname math ->
       let a = args_of call 1 in
       let x = to_float st (expr st a.(0)) in
       fresh st Kfloat (fun r -> Math (List.assoc nname math, r, x))
     | Native { nname = "Abs"; _ } ->
       let a = args_of call 1 in
       (match expr st a.(0) with
        | x, Kfloat -> fresh st Kfloat (fun r -> Math ("fabs", r, x))
        | _ -> raise No)
     | Native { nname = "Len"; _ } ->
       let a = args_of call 1 in
       (match a.(0).e with
        | Var { b = Local i; _ } when st.vecs.(i) <> None -> Int (Option.get st.vecs.(i)).n, Kint
        | _ ->
          let n = array_of st a.(0) in
          fresh st Kint (fun r -> Len (r, n)))
     | Native { nname = "Sum"; _ } when Array.length call.args = 1 && is_vec st call.args.(0).value ->
       (* As Kernels.sum: from 0.0, each cell in turn, then 0.0 + that, so that -0.0 sums to 0.0. *)
       let x = vexpr st (args_of call 1).(0) in
       charge st e x.vn;
       let acc = ref (Ir.Float 0.) in
       for j = 0 to x.vn - 1 do
         let c = x.cell j in
         acc := fst (fresh st Kfloat (fun r -> Op (Fadd, r, !acc, c, -1)))
       done;
       fresh st Kfloat (fun r -> Op (Fadd, r, Float 0., !acc, -1))
     | Native { nname = ("Max" | "Min") as name; _ } when Array.length call.args = 1 && is_vec st call.args.(0).value ->
       (* The best cell, the first of equals: a later one only when it is better. *)
       let x = vexpr st (args_of call 1).(0) in
       charge st e x.vn;
       let acc = ref (x.cell 0) in
       for j = 1 to x.vn - 1 do acc := select st (if name = "Max" then Ir.Gt else Lt) (x.cell j) !acc done;
       !acc, Kfloat
     | Native { nname = ("Max" | "Min") as name; _ } when Array.length call.args = 2 && not (Array.exists (fun (a : arg) -> is_vec st a.value) call.args) ->
       (* Two numbers of one kind: the second when it is better, else the first. *)
       let a = args_of call 2 in
       let x = expr st a.(0) in
       let y = expr st a.(1) in
       (match snd x, snd y with
        | (Ir.Kfloat | Kint), k when k = snd x -> select st ~kind:k (if name = "Max" then Ir.Gt else Lt) (fst y) (fst x), k
        | _ -> raise No)
     | Fun _ when made_here st e <> None -> record st e
     | Fun { proto; env = [||] } ->
       let a = args_of call proto.arity in
       if Array.exists (fun (p : param) -> p.default <> None) proto.func.params then raise No;
       let sg = Array.map (ty st) a in
       (* The interpreter's direct call did the same, with the same types, when it compiled this version
          (Compile.prepare_call): this finds that version, it doesn't make one. *)
       let v = Infer.version_for st.w proto sg in
       if v.state = 0 then Infer.run st.w v;
       if v.state <> 2 then raise No;
       let numbers = Array.for_all (fun t -> t == TI || t == TF) sg && (v.ret == TI || v.ret == TF) in
       (* Values in or out: only inlined, its body made here. *)
       if not (numbers || (st.inl = [] && inlinable ~any:true v && not (own st v))) then raise No;
       let vals = Array.map (expr st) a in
       note st v;
       if st.inl = [] && inlinable ~any:true v && not (own st v) then inline st e v vals else native_call st e v (Array.map fst vals)
     | _ -> raise No)
  | Var { b = Local i; _ } when Vec.get st.kinds (var st i) = Ir.Kval -> call_value st e call (Ir.Reg (var st i))
  | _ -> raise No

(* A literal or a call of a struct's own function: how to lower it, its constant, values, whether they are all
   doubles, and its tag, 8 for a map, 4 for a struct. *)
and made_here st (e : expr) =
  match e.e with
  | Struct_lit { sname; sfields } ->
    Some (fun () -> let c, vals, floats = literal st sname sfields in c, vals, floats, if sname = None then 8 else 4)
  | Call ({ callee = { e = Var { b = Cell { m; k; stable = true }; _ }; _ }; self_tail = false; _ } as call) ->
    (match st.w.modules.(m).cells.(k) with
     | Fun { proto = { func = { body = lazy [| { e = Return { rvalue = Some { e = Struct_lit { sname = Some _ as sname; sfields }; _ }; _ }; _ } |];
                                params; _ }; arity; _ } as proto; env = [||] }
       when Array.for_all (fun (p : param) -> p.ptype = None && p.default = None) params && Array.length params = arity ->
       Some (fun () ->
           let vals, floats = values st (args_of call arity) in
           let c = frame_of_struct st proto sname sfields in
           c, vals, floats, 4)
     | _ -> None)
  | _ -> None

(* A new map or struct, of a literal or of a struct's own function, whose fields take any value: made here, after the
   step and the frame its call takes, checked as an inlined call's. *)
and record st e =
  let c, vals, _, tag = (Option.get (made_here st e)) () in
  alloc st (Array.length vals + 7);
  fresh st Kval (fun r -> Record (r, tag, c, vals))

(* The step and frame of a call of a struct's own function, after its arguments: then its struct, of this constant. *)
and frame_of_struct st (proto : proto) sname sfields =
  note st (Infer.version_for st.w proto (Array.make proto.arity TA));
  let base = match st.inl with [] -> -1 | (vb, _, _) :: _ -> vb in
  let vb = reg st Kint in
  emit st (Frame (vb, base));
  emit st (Enter_or_bail (vb, bail st));
  emit st (Ir.Tick (-1, false, -1));
  let shape = Value.shape_of st.w ?sname ~m:st.w.modules.(proto.pm).host (Array.map fst sfields) in
  const st (Struct { shape; fields = Trie.no_vals; r_owned = false })

(* A call of a function held in a value: a bet on the functions the interpreter saw this call reach, the last first, each
   tested in turn and called as a direct call is; any other goes back to the interpreter. This is the polymorphic inline
   cache of Hölzle, Chambers and Ungar (ECOOP 1991), its entries filled by the interpreter's type feedback. *)
and call_value st e (call : call) f =
  let seen = match List.assoc_opt e.id st.ver.seen with Some l -> !l | None -> [] in
  if seen = [] || List.length seen > Compile.seen_most then raise No;
  let n = Array.length call.args in
  let vals = Array.map (expr st) (args_of call n) in
  let targets = List.filter_map (fun p -> target st p vals) seen in
  if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then
    prerr_endline (Printf.sprintf "jit: call %d reached %d functions, %d taken" e.id (List.length seen) (List.length targets));
  if targets = [] then raise No;
  let k = match targets with (_, (v : version)) :: rest when List.for_all (fun (_, (w : version)) -> w.ret == v.ret) rest -> kind_of v.ret | _ -> Ir.Kval in
  let r = reg st k and join = block st in
  let before = st.dyn.bail and clean = st.dyn.dirty and calm = st.dyn.ticked in
  List.iter
    (fun (p, (v : version)) ->
       let yes = block st and next = block st in
       let c = const st (Fun { proto = p; env = [||] }) in
       close st (Is_fun (f, c, yes, next));
       st.cur <- yes;
       (* Each test runs after the ones before alone: a guard of its arguments may go back as the call's may. *)
       st.dyn.bail <- before;
       st.dyn.dirty <- clean;
       st.dyn.ticked <- calm;
       let args = Array.mapi (fun j (x, xk) -> match v.sg.(j), xk with TI, Ir.Kval -> unbox st x Only_int | TF, Ir.Kval -> unbox st x Only_float | _ -> x, xk) vals in
       note st v;
       let res = if st.inl = [] && inlinable v && not (own st v) then inline st e v args else native_call st e v (Array.map fst args) in
       emit st (Move (r, if k = Ir.Kval then box st res else fst res));
       close st (Jump join);
       st.cur <- next)
    targets;
  st.dyn.bail <- before;
  st.dyn.dirty <- clean;
  st.dyn.ticked <- true;
  close st (Bail (bail st));
  st.cur <- join;
  Ir.Reg r, k

(* A call of a compiled version, native code to native code. When the callee's body starts with a test of its
   parameters that gives one of them or a constant at once, as fib's [n < 2] gives n, that test and that result are made
   here, at the call (partial inlining): half of a tree recursion's calls are leaves, which then cost no call. The call
   is made when the test fails, or when the frame or the fuel of the callee's step is short, which it then handles. *)
and native_call st e (v : version) args =
  st.ncalls <- st.ncalls + 1;
  let back = back st in
  let call () = fresh st (kind_of v.ret) (fun r -> Call (r, callee st v, args, site st e.pos, back)) in
  let f = v.owner.func in
  let np = Array.length f.params in
  let rec simple (x : expr) = match x.e with Lint _ | Lfloat _ -> true | Var { b = Local i; _ } -> i < np | _ -> false
  and test (x : expr) =
    match x.e with
    | Bin ((Lt | Le | Gt | Ge | Eq | Ne), a, b) -> simple a && simple b
    | And (a, b) | Or (a, b) -> test a && test b
    | Not a -> test a
    | _ -> false
  in
  let leaf =
    match Lazy.force f.body with
    | [| { e = If (c, [| y |], _); _ } |] -> Some (c, y)
    | [||] -> None
    | b -> (match b.(0).e with If (c, [| { e = Return { rvalue = Some y; _ }; _ } |], _) -> Some (c, y) | _ -> None)
  in
  match leaf with
  | Some (c, y) when test c && simple y && Array.length args = np && not f.has_self_tail ->
    let k = kind_of v.ret in
    let r = reg st k and quick = block st and burn = block st and slow = block st and cont = block st in
    let base0 = facts st st.cur in
    let blank x = Array.make f.nvars x in
    let child = { st with ver = v; f; regs = blank (-1); arrays = blank (-1); spec = blank false; sunk = blank None; inplace = blank false; fixed = fixed_params f; resumable = false; vecs = blank None; vret = None; flags = blank (-1) } in
    Array.iteri
      (fun j x ->
         let q = reg st (kind_of v.tv.(j)) in
         child.regs.(j) <- q;
         emit st (Move (q, x)))
      args;
    cond child c quick slow;
    st.cur <- quick;
    let vb = reg st Kint in
    emit st (Frame (vb, match st.inl with [] -> -1 | (b, _, _) :: _ -> b));
    close st (Room (vb, burn, slow));
    st.cur <- burn;
    (* The callee's step, as a call's own: the statement may still bail with the fuel it kept. *)
    let calm = st.dyn.callable in
    emit st Burn;
    st.dyn.callable <- calm;
    child.cur <- burn;
    emit st (Move (r, convert child k (expr child y)));
    close st (Jump cont);
    st.cur <- slow;
    emit st (Move (r, fst (call ())));
    goto st cont;
    carry st base0 cont;
    st.dyn.ticked <- true;
    Ir.Reg r, k
  | _ -> call ()

(* A function that a call through a value reached, and the version the interpreter last chose for it, when native code
   can call it as it calls a direct one: a closure of nothing, of numbers in and out, which these arguments can reach. *)
and target st (p : proto) vals =
  match p.last with
  | Last { lver = v; _ }
    when Array.length p.func.captures = 0 && p.arity = Array.length vals && Array.length v.sg = p.arity
         && not (Array.exists (fun (q : param) -> q.default <> None) p.func.params) ->
    if v.state = 0 then Infer.run st.w v;
    let fits t (_, k) = (t == TI && (k = Ir.Kint || k = Kval)) || (t == TF && (k = Ir.Kfloat || k = Kval)) in
    if v.state = 2 && (v.ret == TI || v.ret == TF) && Array.for_all2 fits v.sg vals then Some (p, v) else None
  | _ -> None

(* A condition, as branches: no boolean value is ever made. *)
and cond st (e : expr) yes no =
  match e.e with
  | Not a -> cond st a no yes
  | And (a, b) ->
    let mid = block st in
    cond st a mid no;
    st.cur <- mid;
    cond st b yes no
  | Or (a, b) ->
    let mid = block st in
    cond st a yes mid;
    st.cur <- mid;
    cond st b yes no
  | Lbool true -> close st (Jump yes)
  | Lbool false -> close st (Jump no)
  (* columns.Kind(x) == "float" of an array whose store is known. *)
  | Bin (((Eq | Ne) as op), { e = Call kc; _ }, { e = Ltext t; _ }) when store_kind st kc <> None ->
    close st (Jump (if (Option.get (store_kind st kc) = t) = (op = Eq) then yes else no))
  (* Two tests compared, as (a > 0.0) == (b > 0.0): their truths, words that are equal when both are. *)
  | Bin (((Eq | Ne) as op), a, b) when test_form st a && test_form st b ->
    let x = truth st a in
    let y = truth st b in
    close st (Branch ((if op = Eq then Ir.Eq else Ne), Kint, x, y, yes, no))
  | Bin (((Lt | Le | Gt | Ge | Eq | Ne) as op), a, b) ->
    let op = match op with Lt -> Ir.Lt | Le -> Le | Gt -> Gt | Ge -> Ge | Eq -> Eq | _ -> Ne in
    let x = expr st a in
    let y = expr st b in
    let x, y = numbers st a b x y in
    (match snd x, snd y with
     | Kint, Kint -> close st (Branch (op, Kint, fst x, fst y, yes, no))
     | _ ->
       let x = to_float st x and y = to_float st y in
       close st (Branch (op, Kfloat, x, y, yes, no)))
  | Call call when kind_test st call <> None ->
    let name = Option.get (kind_test st call) in
    (match expr st call.args.(0).value with
     | _, Kint -> close st (Jump (if name = "IsInt" || name = "IsNumber" then yes else no))
     | _, Kfloat -> close st (Jump (if name = "IsFloat" || name = "IsNumber" then yes else no))
     | x, Kval ->
       (* The tag of a block, or 256 + the word of a constant. *)
       let t = fst (fresh st Kint (fun r -> Tag (r, x))) in
       let is c y n = close st (Branch (Eq, Kint, t, Int c, y, n)) in
       let either a b = let mid = block st in is a yes mid; st.cur <- mid; is b yes no in
       (match name with
        | "IsInt" -> is 0 yes no
        | "IsFloat" -> is 1 yes no
        | "IsNumber" -> close st (Branch (Le, Kint, t, Int 1, yes, no))
        | "IsText" -> is 2 yes no
        | "IsArray" -> is 3 yes no
        | "IsDict" -> is 8 yes no
        | "IsFunction" -> either 5 6
        | "IsBool" -> either 261 263
        | _ -> is 257 yes no))
  (* A small function of one test, as isFinite(x) = value.IsNumber(x) and x - x == 0.0: its test made here. *)
  | Call ({ callee = { e = Var { b = Cell { m; k; stable = true }; _ }; _ }; self_tail = false; _ } as call)
    when List.length st.inl < 2 && (match st.w.modules.(m).cells.(k) with Fun { env = [||]; _ } -> true | _ -> false) ->
    (match st.w.modules.(m).cells.(k) with
     | Fun { proto; _ } ->
       let a = args_of call proto.arity in
       if Array.exists (fun (p : param) -> p.default <> None) proto.func.params then raise No;
       let body = (match Lazy.force proto.func.body with [| { e = Return { rvalue = Some b; _ }; _ } |] | [| b |] -> b | _ -> raise No) in
       let v = Infer.version_for st.w proto (Array.map (ty st) a) in
       if v.state = 0 then Infer.run st.w v;
       if not (inlinable ~any:true v) || own st v then raise No;
       let vals = Array.map (expr st) a in
       note st v;
       inline_test st e v vals body yes no
     | _ -> raise No)
  (* A value as a condition: true or false, else the interpreter says what it is. *)
  | Var _ | Field _ | Index _ ->
    (match expr st e with
     | x, Kval ->
       let k = bail st and mid = block st and wrong = block st in
       close st (Branch (Eq, Kint, x, Word 5, yes, mid));
       st.cur <- mid;
       close st (Branch (Eq, Kint, x, Word 7, no, wrong));
       st.cur <- wrong;
       close st (Bail k)
     | _ -> raise No)
  | _ -> raise No

(* What columns.Kind gives of a small array kept in slots or of an array of the region, known by its store. *)
and store_kind st (call : call) =
  match call.callee.e, call.args with
  | Var { b = Cell { m; k; stable = true }; _ }, [| { value = { e = Var { b = Local i; _ }; _ }; aname = None } |]
    when (match st.w.modules.(m).cells.(k) with Native { nname = "Kind"; _ } -> true | _ -> false) ->
    if st.vecs.(i) <> None then Some "float"
    else if st.arrays.(i) >= 0 then Some (match Vec.get st.arr st.arrays.(i) with _, _, 0, _ -> "float" | _, _, 2, _ -> "int" | _ -> "value")
    else None
  | _ -> None

(* [y] when it is better than [x] by [cmp], else [x], as list.Max and list.Min pick. *)
and select ?(kind = Ir.Kfloat) st cmp y x =
  let r = reg st kind and yes = block st and join = block st in
  let base = facts st st.cur in
  emit st (Move (r, x));
  close st (Branch (cmp, kind, y, x, yes, join));
  carry st base yes;
  st.cur <- yes;
  emit st (Move (r, y));
  goto st join;
  carry st base join;
  Reg r

(* The steps of an operation on an array of [n] cells, as the interpreter's natives charge them: n / 16 + 1. *)
and charge st (e : expr) n =
  let s = if st.inl = [] then -1 else site st e.pos in
  for _ = 1 to (n / 16) + 1 do emit st (Ir.Tick (-1, false, s)) done

(* Is [e] a small array of floats by its form: a variable kept so, a literal, or an operation cell by cell with one. A
   call that gives one is one where a small array is wanted. *)
and is_vec st (e : expr) =
  match e.e with
  | Var { b = Local i; _ } -> st.vecs.(i) <> None
  | Array_lit rows ->
    let r = Array.length rows in
    r > 0 && (let c = Array.length rows.(0) in r * c >= 1 && r * c <= vmax)
  | Bin ((Add | Sub | Mul | Div), a, b) -> is_vec st a || is_vec st b
  | Neg a -> is_vec st a
  | Call call -> elementwise st call <> None
  | _ -> false

(* A native that works cell by cell on a small array here: math.Abs and the functions of libm, list.Max and list.Min of
   two. *)
and elementwise st (call : call) =
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; _ } when Array.for_all (fun (a : arg) -> a.aname = None) call.args ->
    (match st.w.modules.(m).cells.(k), call.args with
     | Native { nname = "Abs"; _ }, [| a |] when is_vec st a.value -> Some "fabs"
     | Native { nname; f1 = Some _; _ }, [| a |] when List.mem_assoc nname math && is_vec st a.value -> Some (List.assoc nname math)
     | Native { nname = ("Max" | "Min") as n; _ }, [| a; b |] when is_vec st a.value || is_vec st b.value -> Some n
     | _ -> None)
  | _ -> None

(* An operand of an operation cell by cell: a small array, or a number made a float, once, as the interpreter's
   operation takes it. *)
and operand_v ?(floats = false) st (e : expr) =
  let scalar () =
    match expr st e with
    | _, Ir.Kint when floats -> raise No
    | x, Kval when floats -> `S (fst (unbox st x Only_float))
    | x -> `S (to_float st x)
  in
  let calls = ref false in
  walk (fun (x : expr) -> (match x.e with Call _ -> calls := true | _ -> ()); true) e;
  if is_vec st e then `V (vexpr st e)
  else if !calls then begin
    (* A call may give a number or a small array: a number first, else, that code dropped, an array. *)
    let undo = saved st in
    try scalar () with No -> undo (); `V (vexpr st e)
  end
  else scalar ()

(* The shape of an operation cell by cell on [x] and [y]: one of them a small array, both of the same rows and columns. *)
and shape_of x y =
  match x, y with
  | `V p, `V q -> if p.vr <> q.vr || p.vc <> q.vc then raise No else p
  | `V p, `S _ | `S _, `V p -> p
  | `S _, `S _ -> raise No

(* A small array of floats: [e] made as one, its cells made where asked. *)
and vexpr st (e : expr) : vec =
  let get o j = match o with `V p -> p.cell j | `S s -> s in
  match e.e with
  | Var { b = Local i; _ } when st.vecs.(i) <> None ->
    let v = Option.get st.vecs.(i) in
    { vn = v.n; vr = v.rows; vc = v.cols; at = v.slot; cell = (fun j -> fst (fresh st Kfloat (fun r -> Vget (r, v.slot + j)))) }
  | Array_lit rows ->
    let r = Array.length rows in
    let c = if r = 0 then 0 else Array.length rows.(0) in
    if r * c < 1 || r * c > vmax || Array.exists (fun row -> Array.length row <> c) rows then raise No;
    (* Each cell in the order of the source, row by row, as the interpreter's literal, kept column by column; floats
       alone make a store of floats. *)
    let cells = Array.make (r * c) (Ir.Float 0.) in
    Array.iteri
      (fun i row ->
         Array.iteri
           (fun j (x : expr) ->
              let v =
                match expr st x with
                | v, Ir.Kfloat -> v
                | v, Kval when st.dyn.bail <> None && (match observe st x with Some (Float _) | None -> true | _ -> false) ->
                  fst (unbox st v Only_float)
                | _ -> raise No
              in
              cells.((j * r) + i) <- v)
           row)
      rows;
    { vn = r * c; vr = r; vc = c; at = -1; cell = (fun j -> cells.(j)) }
  | Bin (((Add | Sub | Mul | Div) as op), a, b) ->
    let fop = match op with Add -> Ir.Fadd | Sub -> Fsub | Mul -> Fmul | _ -> Fdiv in
    let x = operand_v st a in
    let y = operand_v st b in
    let sh = shape_of x y in
    charge st e sh.vn;
    { sh with at = -1; cell = (fun j -> let u = get x j in let w = get y j in fst (fresh st Kfloat (fun r -> Op (fop, r, u, w, -1)))) }
  | Neg a ->
    let x = vexpr st a in
    charge st e x.vn;
    { x with at = -1; cell = (fun j -> let u = x.cell j in fst (fresh st Kfloat (fun r -> Fneg (r, u)))) }
  | Call call when elementwise st call <> None ->
    (match Option.get (elementwise st call), call.args with
     | ("Max" | "Min") as name, [| a; b |] ->
       let x = operand_v ~floats:true st a.value in
       let y = operand_v ~floats:true st b.value in
       let sh = shape_of x y in
       charge st e sh.vn;
       { sh with at = -1; cell = (fun j -> let u = get x j in let w = get y j in select st (if name = "Max" then Ir.Gt else Lt) w u) }
     | f, [| a |] ->
       let x = vexpr st a.value in
       charge st e x.vn;
       { x with at = -1; cell = (fun j -> let u = x.cell j in fst (fresh st Kfloat (fun r -> Math (f, r, u)))) }
     | _ -> raise No)
  | Call call -> vcall st e call
  | _ -> raise No

(* Slots of the frame's area of small arrays, [n] of them, the first one's number. *)
and take st n =
  let k = st.dyn.vslots in
  st.dyn.vslots <- k + n;
  k

(* The cells of [x] into the slots from [k]. Each cell reads only the same cell of what it is made of, so [k] may be one
   of those. *)
and vstore st (x : vec) k = for j = 0 to x.vn - 1 do emit st (Vset (k + j, x.cell j)) done

(* An argument of a call: a small array in slots, or a value. *)
and argv st (e : expr) =
  if is_vec st e then begin
    let x = vexpr st e in
    let k = if x.at >= 0 then x.at else (let k = take st x.vn in vstore st x k; k) in
    `V (k, x)
  end
  else `S (expr st e)

(* A call that gives a small array of floats: of a function named or held in a value, inlined, its body's array in slots
   of its own. *)
and vcall st (e : expr) (call : call) : vec =
  if call.self_tail || st.inl <> [] then raise No;
  let made (out : vout) =
    if out.out < 0 then raise No;
    let vn, vr, vc = out.shape in
    { vn; vr; vc; at = out.out; cell = (fun j -> fst (fresh st Kfloat (fun r -> Vget (r, out.out + j)))) }
  in
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; _ } ->
    (match st.w.modules.(m).cells.(k) with
     | Fun { proto; env = [||] } ->
       let a = args_of call proto.arity in
       if Array.exists (fun (p : param) -> p.default <> None) proto.func.params then raise No;
       let v = Infer.version_for st.w proto (Array.map (ty st) a) in
       if v.state = 0 then Infer.run st.w v;
       if v.state <> 2 || (not (inlinable ~any:true ~most:vbody v)) || own st v then raise No;
       let args = Array.map (argv st) a in
       note st v;
       let out = { out = -1; shape = (0, 0, 0) } in
       ignore (inline_args st e v args (Some out));
       made out
     | _ -> raise No)
  | Var { b = Local i; _ } when plain st i && st.regs.(i) >= 0 && Vec.get st.kinds st.regs.(i) = Ir.Kval ->
    (* Through a value: the bet of [call_value] on the functions the interpreter saw, each inlined. *)
    let f = Ir.Reg st.regs.(i) in
    let seen = match List.assoc_opt e.id st.ver.seen with Some l -> !l | None -> [] in
    if seen = [] || List.length seen > Compile.seen_most then raise No;
    let args = Array.map (argv st) (args_of call (Array.length call.args)) in
    let targets = List.filter_map (fun p -> vtarget st p args) seen in
    if targets = [] then raise No;
    let out = { out = -1; shape = (0, 0, 0) } and join = block st in
    let before = st.dyn.bail and clean = st.dyn.dirty and calm = st.dyn.ticked and dead = st.dyn.dead in
    List.iter
      (fun (p, (v : version)) ->
         let yes = block st and next = block st in
         let c = const st (Fun { proto = p; env = [||] }) in
         close st (Is_fun (f, c, yes, next));
         st.cur <- yes;
         st.dyn.bail <- before;
         st.dyn.dirty <- clean;
         st.dyn.ticked <- calm;
         st.dyn.dead <- dead;
         note st v;
         ignore (inline_args st e v args (Some out));
         close st (Jump join);
         st.cur <- next)
      targets;
    st.dyn.bail <- before;
    st.dyn.dirty <- clean;
    st.dyn.ticked <- true;
    st.dyn.dead <- dead;
    close st (Bail (bail st));
    st.cur <- join;
    made out
  | _ -> raise No

(* A function a call through a value reached that native code can inline with these arguments, small arrays among them:
   a closure of nothing, as [target]'s. *)
and vtarget st (p : proto) args =
  match p.last with
  | Last { lver = v; _ }
    when Array.length p.func.captures = 0 && p.arity = Array.length args && Array.length v.sg = p.arity
         && not (Array.exists (fun (q : param) -> q.default <> None) p.func.params) ->
    if v.state = 0 then Infer.run st.w v;
    let fits t a =
      match a with
      | `V _ -> t == TFA || t == TA
      | `S (_, k) -> t == TA || (t == TI && (k = Ir.Kint || k = Kval)) || (t == TF && (k = Ir.Kfloat || k = Kval))
    in
    if v.state = 2 && inlinable ~any:true ~most:vbody v && (not (own st v)) && Array.for_all2 fits v.sg args then Some (p, v) else None
  | _ -> None

(* The small array an inlined body gives: into the slots of the call's, the first one given making them. *)
and vgive st (x : vec) =
  let o = Option.get st.vret in
  if o.out < 0 then begin
    o.out <- take st x.vn;
    o.shape <- (x.vn, x.vr, x.vc)
  end
  else if o.shape <> (x.vn, x.vr, x.vc) then raise No;
  vstore st x o.out;
  match st.ret_to with Some (_, cont) -> close st (Jump cont) | None -> raise No

(* Is [e] a test by its form: its value is true or false. *)
and test_form st (e : expr) =
  match e.e with
  | Bin ((Lt | Le | Gt | Ge | Eq | Ne), _, _) | And _ | Or _ | Not _ | Lbool _ -> true
  | Call call -> kind_test st call <> None
  | _ -> false

(* A call of value.IsNumber and its kind: which one. *)
and kind_test st (call : call) =
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; _ } when Array.length call.args = 1 && call.args.(0).aname = None ->
    (match st.w.modules.(m).cells.(k) with
     | Native { nname = ("IsInt" | "IsFloat" | "IsNumber" | "IsText" | "IsArray" | "IsDict" | "IsFunction" | "IsBool"
                        | "IsMissing") as n; _ } -> Some n
     | _ -> None)
  | _ -> None

(* The value of a test, true or false as the words of [Types.t]; any other value as it is. *)
and truth st (e : expr) =
  match e.e with
  | Lbool b -> Ir.Word (if b then 5 else 7)
  | _ when test_form st e ->
    let r = reg st Kval and y = block st and n = block st and join = block st in
    let b0 = st.cur in
    cond st e y n;
    let base = facts st b0 in
    carry st base y;
    st.cur <- y;
    emit st (Move (r, Word 5));
    goto st join;
    carry st base n;
    st.cur <- n;
    emit st (Move (r, Word 7));
    goto st join;
    carry st base join;
    Reg r
  | _ -> (match expr st e with x, Kval -> x | _ -> raise No)

(* A call of a small function of one test, inlined as a test: its frame, its step, then its test, to [yes] or [no]. *)
and inline_test st (e : expr) (v : version) args body yes no =
  let callsite = site st e.pos in
  let base = match st.inl with [] -> -1 | (vb, _, _) :: _ -> vb in
  let vb = reg st Kint in
  emit st (Frame (vb, base));
  emit st (Enter (vb, base, callsite, back st));
  let f = v.owner.func in
  let child =
    { st with ver = v; f; regs = Array.make f.nvars (-1); arrays = Array.make f.nvars (-1); spec = Array.make f.nvars false;
              sunk = Array.make f.nvars None; inplace = Array.make f.nvars false; loops = [];
              inl = (vb, base, callsite) :: st.inl; ret_to = None; body = 0; region = false; fast = Hashtbl.create 1;
              fixed = fixed_params f; resumable = false; vecs = Array.make f.nvars None; vret = None; flags = Array.make f.nvars (-1) }
  in
  Array.iteri
    (fun j (x, xk) ->
       let r = match v.tv.(j) with TI | TF -> reg st (kind_of v.tv.(j)) | _ -> reg st xk in
       child.regs.(j) <- r;
       emit child (Move (r, convert child (Vec.get st.kinds r) (x, xk))))
    args;
  emit child (Ir.Tick (-1, false, site child e.pos));
  cond child body yes no;
  st.ncalls <- child.ncalls + 1

and stmt st (e : expr) =
  match e.e with
  | Assign ({ b = Local i; _ }, { e = Index (b, [| Ix ix |], false); pos; _ }) when sunk_map st i ->
    (* p = ps[i]: the map's values into the registers that stand for p; nothing after it can fail. *)
    let s = Option.get st.sunk.(i) in
    let a = array_of st b in
    let k = (match guess st ix (expr st ix) with x, Kint -> x | _ -> raise No) in
    let m = fst (fresh st Kval (fun r -> Get (r, a, k, site st pos))) in
    let d =
      match s.carrier with
      | Struct { shape; _ } -> checked st m (-1 - (2 * shape.sid)) (fun r -> Ir.Fields (r, m, shape.sid, 0, bail st))
      | carrier -> let c = const st carrier in checked st m (2 * c) (fun r -> Ir.Vals (r, m, c, 0, bail st))
    in
    Array.iteri (fun j p -> emit st (Load (p, d, j, -1))) s.parts;
    (match m with Reg q -> st.dyn.elems <- (st.cur, a, k, (q, d)) :: st.dyn.elems | _ -> ());
    st.dyn.dirty <- true
  | Assign ({ b = Local i; _ }, v) when st.vecs.(i) <> None ->
    (* A small array: its cells into the variable's slots, after everything that may go back. *)
    let d = Option.get st.vecs.(i) in
    let x = vexpr st v in
    if x.vn <> d.n || x.vr <> d.rows || x.vc <> d.cols then raise No;
    if x.at <> d.slot then vstore st x d.slot;
    if st.flags.(i) >= 0 then emit st (Move (st.flags.(i), Int 1));
    shows st
  | Assign ({ b = Local i; _ }, v) when st.inl <> [] && st.ver.tv.(i) == TA && plain st i ->
    (* A variable of no type of an inlined body: a register of the kind of the first value assigned, which every other
       must have. *)
    let x, k = expr st v in
    if st.regs.(i) < 0 then st.regs.(i) <- reg st k;
    if Vec.get st.kinds st.regs.(i) <> k then raise No;
    emit st (Move (st.regs.(i), x))
  | Assign ({ b = Local i; _ }, v) ->
    let r = var st i in
    let x =
      match Vec.get st.kinds r with
      | Kval ->
        (* A value read elsewhere and held by a variable alone is marked shared when the run writes the variable back:
           nothing in native code changes it in place. *)
        (match expr st v with
         | x, Kval ->
           (match v.e with Var _ | Index _ | Field _ when not (List.mem r st.dyn.lent) -> st.dyn.lent <- r :: st.dyn.lent | _ -> ());
           x
         | x -> box st x)
      | k when st.spec.(i) ->
        (* A number for the whole run: the value assigned must be one of its kind, checked, or the loop lowers again with
           the variable a value. *)
        let x =
          match expr st v with
          | x, k' when k' = k -> x
          | x, Kval when st.dyn.bail <> None -> fst (unbox st x (if k = Kint then Only_int else Only_float))
          | _ -> raise (Respec i)
        in
        x
      | k -> convert st k (expr st v)
    in
    emit st (Move (r, x));
    if st.flags.(i) >= 0 then emit st (Move (st.flags.(i), Int 1));
    (* An inlined callee's variables are its own: the way back has nothing of them to put back. *)
    if st.inl = [] then st.dyn.dirty <- true
  | Set { root = { b = Local i; _ }; path = [| { sk = Sindex (_, false); _ } |]; value }
    when st.arrays.(i) >= 0 && Hashtbl.mem st.fast e.id ->
    let a, ix, k = Hashtbl.find st.fast e.id in
    let x = cell_value st a value in
    emit st (Set_at (a, ix, k, x))
  | Set { root = { b = Local i; _ }; path = [| { sk = Sindex ([| Ix ix |], false); sp } |]; value } when st.arrays.(i) >= 0 ->
    let a = st.arrays.(i) in
    let k = (match guess st ix (expr st ix) with x, Kint -> x | _ -> raise No) in
    let slot, _, store, nd = Vec.get st.arr a in
    Vec.set st.arr a (slot, true, store, nd);
    (match store, value.e with
     | 1, (Struct_lit _ | Call _) when st.inplace.(i) && made_here st value <> None ->
       (* A map or struct of floats written over an owned one of the same keys or shape and store: its doubles, in
          place. *)
       let c, vals, floats, tag = Option.get (made_here st value) () in
       (* The map or struct read there in this turn, checked then, when nothing wrote the list since. *)
       let seen = List.find_map (fun (b, a', i, x) -> if b = st.cur && a' = a && i = k then Some x else None) st.dyn.elems in
       (* When the one there can't take the doubles, the interpreter makes the write, back at the statement's start
          with its fuel, where it can: no call in the loop, so MIR keeps no register in memory around one. *)
       let back = match st.dyn.callable with Some _ when floats && not st.dyn.dirty -> back st | _ -> -1 in
       if back < 0 then alloc st (Array.length vals + 7);
       if floats then emit st (Into (a, k, vals, c, tag, site st sp, seen, back))
       else begin
         let m = fst (fresh st Kval (fun r -> Record (r, tag, c, vals))) in
         emit st (Put (a, k, m, site st sp))
       end
     | _ ->
       (* As the interpreter's write: the index, then the value, then the array, which an F store takes only as a number. *)
       let x = if store = 1 then stored st value else cell_value st a value in
       (* At the step, as the interpreter names an index outside the array. *)
       emit st (if store = 1 then Put (a, k, x, site st sp) else Set_elem (a, k, x, site st sp)))
  | Set { root = { b = Local i; _ }; path = [| { sk = Sindex (ixs, false); sp } |]; value }
    when st.arrays.(i) >= 0 && Array.length ixs >= 2 ->
    let a = st.arrays.(i) in
    let xs = indexes st a ixs in
    let x = (let _, _, store, _ = Vec.get st.arr a in if store = 1 then stored st value else cell_value st a value) in
    let slot, _, store, nd = Vec.get st.arr a in
    Vec.set st.arr a (slot, true, store, nd);
    let q = cell st a xs sp true in
    emit st (if store = 1 then Put (a, Reg q, x, site st sp) else Set_at (a, q, 0, x))
  | For { var = { b = Local i; _ }; iter = { e = Range (a, b); _ }; fbody; _ } ->
    let lo = expr st a in
    let hi = expr st b in
    if snd lo <> Kint || snd hi <> Kint then raise No;
    inner_loop st (fun () -> ignore (for_loop ~lo:(fst lo, fst hi) st e i fbody))
  | While { cond = c; body; _ } ->
    inner_loop st (fun () ->
        let pre = block st and head = block st and inside = block st and exit = block st in
        goto st pre;
        goto st head;
        (* The room before the test, so that the run comes back before it, outside the loop: a loop has one join. *)
        if allocates st body then reserve ~resume:pre st;
        cond st c inside exit;
        st.cur <- inside;
        loop_in st exit (fun () -> Array.iter (stmt st) body);
        let p = point st pre in
        emit st (Ir.Tick (p, outer st, -1));
        Vec.add_last st.infos (e.id, -1, -1, p);
        close st (Jump head);
        st.cur <- exit)
  | If (c, yes, no) ->
    let y = block st and n = block st and join = block st in
    let b0 = st.cur in
    cond st c y n;
    (* What the block of the test knew holds in both branches, and what both knew at their end holds after them. *)
    let base = facts st b0 in
    (* Either branch runs after the test alone: a guard in it may go back while nothing of the branch showed. *)
    let before = st.dyn.bail and clean = st.dyn.dirty and calm = st.dyn.ticked in
    carry st base y;
    st.cur <- y;
    assume st c true (fun () -> branch st yes);
    let end_yes = facts st st.cur and dead_yes = st.dyn.dead in
    goto st join;
    let after_yes = st.dyn.bail and dirty_yes = st.dyn.dirty and ticked_yes = st.dyn.ticked in
    st.dyn.bail <- before;
    st.dyn.dirty <- clean;
    st.dyn.ticked <- calm;
    st.dyn.dead <- false;
    carry st base n;
    st.cur <- n;
    assume st c false (fun () -> branch st no);
    let end_no = facts st st.cur and dead_no = st.dyn.dead in
    goto st join;
    (* A branch left to the interpreter never comes to the join: what the other knew holds there. *)
    if dead_yes then carry st end_no join else if dead_no then carry st end_yes join else meet st end_yes end_no join;
    st.dyn.dead <- dead_yes && dead_no;
    if after_yes = None then shows st;
    st.dyn.dirty <- st.dyn.dirty || dirty_yes;
    st.dyn.ticked <- st.dyn.ticked || ticked_yes
  | Break ->
    (match st.loops with
     | l :: _ ->
       close st (Jump l);
       st.cur <- block st
     | [] -> raise No)
  | Return { rvalue = Some v; _ } when st.vret <> None ->
    vgive st (vexpr st v);
    st.cur <- block st
  | Return { rvalue = Some v; _ } when st.ret_to <> None ->
    result st (expr st v);
    st.cur <- block st
  | Return { rvalue = Some v; _ } when st.ver.ret == TI || st.ver.ret == TF ->
    let x = convert st (kind_of st.ver.ret) (expr st v) in
    if st.region then close st (Out x) else give st x;
    st.cur <- block st
  | Return { rvalue = Some v; _ } when st.region ->
    (* A value, of a function whose result has no kind: stored, as the interpreter's return gives it. *)
    close st (Out (stored st v));
    st.cur <- block st
  | Lint _ | Lfloat _ -> ()
  (* Native code runs no hook: a line with a breakpoint stays with the interpreter. *)
  | Hook h -> if Debug.armed st.w st.ver.owner.file (Pos.line e.pos) then raise No else st.live <- h.live
  (* A variable alone reads it: one that may be unset, or of the module, stays with the interpreter, which says so. *)
  | Var { b = Local i; _ } when plain st i && (st.regs.(i) >= 0 || st.arrays.(i) >= 0) -> ()
  | Var _ -> raise No
  | Call _ | Bin _ | Neg _ | Index _ -> ignore (expr st e)
  | _ -> raise No

(* A loop inside another: it shows at once, and the allocation after it takes room of its own. *)
and inner_loop st f =
  shows st;
  let around = st.dyn.need and resumable = st.resumable in
  st.dyn.need <- None;
  st.resumable <- false;
  f ();
  st.resumable <- resumable;
  st.dyn.need <- None;
  if around <> None then reserve st

(* Room for the allocations of a loop's step, checked once at its top: there, when the young heap lacks it, the run leaves
   and comes back once the interpreter's allocation collected, at [resume], a block before the loop that leads to the same
   place, else at a block of its own. *)
and reserve ?resume st =
  let l = match resume with Some l -> l | None -> let l = block st in goto st l; l in
  let need = ref 0 in
  emit st (Reserve (need, point st l));
  st.dyn.need <- Some need

(* Can these statements allocate, outside the loops inside them: a map or struct made, a number stored as a value. *)
and allocates st (b : block) =
  let rec made (e : expr) =
    match e.e with
    | Struct_lit _ -> true
    | Bin (_, x, y) | And (x, y) | Or (x, y) -> made x || made y
    | Neg x | Not x | Field (x, _) | Return { rvalue = Some x; _ } -> made x
    | If (c, y, n) -> made c || Array.exists made y || Array.exists made n
    | Index (x, a, _) -> made x || Array.exists (function Ix i -> made i | All -> false) a
    | Call c ->
      (match c.callee.e with
       | Var { b = Cell { m; k; stable = true }; _ } ->
         (* An inlined body may make a map or box a number. *)
         (match st.w.modules.(m).cells.(k) with Fun _ -> true | _ -> false)
       (* A call through a value may box what its functions give. *)
       | Var { b = Local _; _ } -> true
       | _ -> false)
      || Array.exists (fun (a : arg) -> made a.value) c.args
    | Assign ({ b = Local i; _ }, v) -> (st.regs.(i) >= 0 && Vec.get st.kinds st.regs.(i) = Ir.Kval) || made v
    | Set { root = { b = Local i; _ }; value; _ } ->
      (st.arrays.(i) >= 0 && (let _, _, store, _ = Vec.get st.arr st.arrays.(i) in store = 1)) || made value
    | _ -> false
  in
  Array.exists made b

(* The statements of a loop's body; those of the region's own loop each say where a guard goes back to. *)
and stmts st ~root (b : block) =
  if root then begin
    while Vec.length st.dyn.points < Array.length b do Vec.add_last st.dyn.points (-1) done;
    st.resumable <- true;
    Array.iteri (fun k x -> resume_at st k x ~nested:false) b;
    st.resumable <- false;
    shows st
  end else Array.iter (stmt st) b

(* Statement [x] as point [k], which a guard in it goes back to, its variables and fuel put back. One in a branch of the
   region's ifs that doesn't lower, or that a lowering before found so, is left to the interpreter: the run bails before
   it, and the rest of its block isn't made, as it never runs here. *)
and resume_at st k (x : expr) ~nested =
  (* The variables the statement may assign, whose copies the way back may need, made at its start. *)
  let vars = try List.sort_uniq compare (assigned ~sets:false ~cold:st.cold [] x) with Unknown -> [] in
  st.dyn.vars <- List.filter (fun r -> r >= 0) (List.map (fun i -> st.regs.(i)) vars);
  st.dyn.start <- (st.cur, List.length (Vec.get st.blocks st.cur).ins);
  while Vec.length st.dyn.restores <= k do Vec.add_last st.dyn.restores [] done;
  while Vec.length st.dyn.keeps <= k do Vec.add_last st.dyn.keeps (-1, -1, -1) done;
  st.dyn.bail <- Some k;
  st.dyn.callable <- Some k;
  st.dyn.dirty <- false;
  st.dyn.ticked <- false;
  st.dyn.copies <- (false, false);
  st.dyn.dead <- false;
  (* One the loop's variables were looked at without ([dead]) is the interpreter's. *)
  if nested && List.mem x.id st.cold then cold st k x
  else if nested then begin
    let undo = saved st in
    match stmt st x with
    | () -> ()
    | exception No ->
      undo ();
      st.dyn.colds <- x.id :: st.dyn.colds;
      cold st k x
  end
  else stmt st x

(* A bail before statement [k], which the interpreter makes: a [return] leaves the loop, at most once a run. *)
and cold st k (x : expr) =
  close st (Bail ((match x.e with Return _ -> Ir.leaving | _ -> Ir.cold) + k));
  st.cur <- block st;
  st.dyn.dead <- true

(* The state of the lowering now, and a function that puts it back, the code made since dropped: what a statement that
   doesn't lower left behind. *)
and saved st =
  let d = st.dyn in
  let b = st.cur and n = List.length (Vec.get st.blocks st.cur).ins and start = d.start and starts = List.length d.starts in
  let bail = d.bail and callable = d.callable and dirty = d.dirty and ticked = d.ticked and copies = d.copies and vars = d.vars in
  let shrink v k = let a = Vec.to_array v in Vec.clear v; Array.iteri (fun i x -> if i < k then Vec.add_last v x) a in
  let arr = Vec.to_array st.arr and resumes = Vec.length st.resumes and infos = Vec.length st.infos in
  let hidden = Vec.length st.hidden and points = Vec.length d.points and need = Option.map ( ! ) d.need in
  let loose = d.loose and lent = d.lent and known = d.known and nums = d.nums and elems = d.elems and ranges = d.ranges in
  let inside = d.inside and colds = d.colds and ncalls = st.ncalls and fast = st.fast and resumable = st.resumable in
  let twins = Hashtbl.copy st.twins in
  fun () ->
    let blk = Vec.get st.blocks b in
    let rec drop k l = if k = 0 then l else drop (k - 1) (List.tl l) in
    (* What [at_start] put in this block since stays, before the code dropped: its registers' copies and fuel. *)
    let rec moved k l = if k = 0 then 0 else match l with x :: r -> (if x = b then 1 else 0) + moved (k - 1) r | [] -> 0 in
    let extra = moved (List.length d.starts - starts) d.starts in
    blk.ins <- drop (List.length blk.ins - n - extra) blk.ins;
    st.cur <- b;
    d.start <- start;
    d.bail <- bail;
    d.callable <- callable;
    d.dirty <- dirty;
    d.ticked <- ticked;
    d.copies <- copies;
    d.vars <- vars;
    Array.iteri (Vec.set st.arr) arr;
    shrink st.resumes resumes;
    shrink st.infos infos;
    shrink st.hidden hidden;
    shrink d.points points;
    (match d.need, need with Some r, Some x -> r := x | _ -> ());
    d.loose <- loose;
    d.lent <- lent;
    d.known <- known;
    d.nums <- nums;
    d.elems <- elems;
    d.ranges <- ranges;
    d.inside <- inside;
    d.colds <- colds;
    d.dead <- false;
    st.ncalls <- ncalls;
    st.fast <- fast;
    Hashtbl.reset st.twins;
    Hashtbl.iter (Hashtbl.replace st.twins) twins;
    st.resumable <- resumable

(* The statements of a branch of an if: in the region's loop, each a point of its own, numbered after the loop's. *)
and branch st (b : block) =
  if not st.resumable then Array.iter (fun x -> if not st.dyn.dead then guarded st x) b
  else
    (* After one left to the interpreter, the rest of the block is the interpreter's too. *)
    Array.iter
      (fun (x : expr) ->
         if not st.dyn.dead then begin
           let k = Vec.push st.dyn.points x.id in
           resume_at st k x ~nested:true
         end)
      b

(* A [for] over a..b. The counter is the loop's variable itself when the body leaves it alone, else a hidden slot; the
   bound is a hidden slot. With [lo] given, they start at it and at the bound; else they are in their slots (a region's
   loop). An innermost loop, with no loop and no call inside, also gets a fast copy, taken when, before it starts, the
   fuel covers all its steps and each index that is a + b·counter is proved inside its array at both ends, every part of
   it without overflow: that copy checks neither, and moves those indexes by their step. The checked copy runs
   otherwise. A loop around innermost ones gets a fast copy too, of its indexes counter + k only, its steps counted
   (loop versioning, Midkiff, Moreira and Snir, 1998). A run that leaves comes back before the loop, through [decide], never into its body: the loop's one join is
   its body's start, where only what the loop changes meets (Fink and Qian's entry at the head of a loop), so MIR puts no
   copies of the other variables in it. Gives the block that tests the counter. *)
and for_loop ?lo ?(root = false) st (e : expr) i fbody =
  let r = var st i in
  (* The interpreter hands a [for] over to native code, and takes it back, only for a variable of integers: another
     one's loop keeps its counter and bound to itself, and a run that came back inside would not find them. *)
  if Vec.get st.kinds r <> Kint || st.ver.tv.(i) != TI then raise No;
  let written = try Some (Array.fold_left (assigned ~cold:st.cold) [] fbody) with Unknown -> None in
  let own = match written with Some l -> not (List.mem i l) | None -> false in
  match Hashtbl.find_opt st.twins e.id, lo with
  | Some tw, Some (l, x) -> twin_loop st e i fbody written tw l x
  | _ ->
  let c = if own then r else hidden st in
  let cslot = if own then st.ver.map.(i) else (Vec.get_last st.hidden).slot in
  let h = hidden st in
  let hslot = (Vec.get_last st.hidden).slot in
  let head = block st and decide = block st and body = block st and next = block st and inc = block st and exit = block st in
  let again = block st and step = block st in
  (match lo with
   | Some (l, x) ->
     (* An empty range leaves the variable as it was, as the interpreter's loop never writes it: the counter, which may be
        the variable, is set only once the range is known not to be empty; the head's test is then known too. *)
     emit st (Move (h, x));
     let start = block st in
     close st (Branch (Gt, Kint, l, Reg h, exit, start));
     st.cur <- start;
     emit st (Move (c, l));
     close st (Jump decide)
   (* A region's loop, entered at its points: the block before still leads to the head, so that its loops are loops from
      the function's entry, as MIR's allocator wants them. *)
   | None -> close st (Jump head));
  st.cur <- head;
  close st (Branch (Gt, Kint, Reg c, Reg h, exit, decide));
  st.cur <- body;
  let calls = st.ncalls in
  let need = if allocates st fbody then (reserve ~resume:decide st; st.dyn.need) else None in
  (* The room's point comes back before the loop: only the body's own points and calls rule out its fast copy, and an
     allocation, which the fast copy makes no room for. *)
  let points = Vec.length st.resumes in
  if not own then emit st (Move (r, Reg c));
  loop_in st exit (fun () -> stmts st ~root fbody);
  let inner = Vec.length st.resumes = points && st.ncalls = calls && (match need with Some n -> !n = 0 | None -> true) in
  let p = tick ~resume:again st next in
  Vec.add_last st.infos (e.id, cslot, hslot, p);
  Hashtbl.replace st.twins e.id { tc = c; th = h; tbody = body; tinner = inner };
  close st (Branch (Eq, Kint, Reg c, Reg h, exit, inc));
  st.cur <- inc;
  emit st (Incr c);
  close st (Jump body);
  (* After a step, from outside: the same test and step, then the loop from its start. *)
  st.cur <- again;
  close st (Branch (Eq, Kint, Reg c, Reg h, exit, step));
  st.cur <- step;
  emit st (Incr c);
  close st (Jump decide);
  st.cur <- decide;
  (match written with
   | Some written when inner -> ignore (fast_copy st e i c h fbody written ~root ~slow:body ~exit)
   (* A loop whose loops inside are innermost [for]s that allocate nothing, and that allocates nothing itself: its
      indexes' bounds checked once before it, its steps counted as it goes. A run that comes back inside it comes back
      into the slow copy, whose turns then go through [decide] again, so the next turn is the fast copy's. One level
      only, so that an innermost body is made at most four times. *)
   | Some written when (match need with Some n -> !n = 0 | None -> true) && nest fbody = 1 && plain_fors st fbody ->
     if fast_copy ~again:p st e i c h fbody written ~root ~slow:body ~exit then (Vec.get st.blocks inc).term <- Jump decide
   | _ -> close st (Jump body));
  st.cur <- exit;
  head

(* A loop inside a loop's fast copy, made a second time: the twin of the first, of the same counter and bound, holds
   only its own fast copy, and leaves for the first's slow copy, with the rest of the loop around it, when that fast
   copy's checks fail. So no point of the run comes back inside the fast copy around it, whose checks it would not have
   made, and the code is not made twice. *)
and twin_loop st (e : expr) i fbody written tw l x =
  let c = tw.tc and h = tw.th and decide = block st and exit = block st in
  emit st (Move (h, x));
  let start = block st in
  close st (Branch (Gt, Kint, l, Reg h, exit, start));
  st.cur <- start;
  emit st (Move (c, l));
  goto st decide;
  (match written with
   | Some written when tw.tinner -> ignore (fast_copy st e i c h fbody written ~root:false ~slow:tw.tbody ~exit)
   | _ -> close st (Jump tw.tbody));
  st.cur <- exit;
  decide

(* Are the loops in [b] [for]s over a range whose bodies allocate nothing. *)
and plain_fors st (b : block) =
  let ok = ref true in
  Array.iter
    (walk (fun (x : expr) ->
         match x.e with
         | For { iter = { e = Range _; _ }; fbody; _ } -> if allocates st fbody then ok := false; false
         | For _ | While _ -> ok := false; false
         | _ -> true))
    b;
  !ok

and fast_copy ?again st _e i c h fbody written ~root ~slow ~exit =
  (* The checks before the loop run one after the other, each block after the one before: an operation, a size or a test
     made once serves every index after it. [dry]: only whether an index is affine, nothing made. *)
  let made = Hashtbl.create 16 and sizes = Hashtbl.create 8 and tested = Hashtbl.create 16 and dry = ref false in
  let t op x y =
    match op, x, y with
    | (Ir.Add | Sub), _, Ir.Int 0 -> x
    | Add, Ir.Int 0, _ -> y
    | Mul, _, Ir.Int 0 | Mul, Ir.Int 0, _ -> Int 0
    | Mul, _, Ir.Int 1 -> x
    | Mul, Ir.Int 1, _ -> y
    | (Add | Sub | Mul), Ir.Int p, Ir.Int q when abs p < 1 lsl 30 && abs q < 1 lsl 30 ->
      Int (match op with Add -> p + q | Sub -> p - q | _ -> p * q)
    | _ when !dry -> Ir.Reg (-1)
    | _ ->
      (match Hashtbl.find_opt made (op, x, y) with
       | Some v -> v
       | None ->
         let r = reg st Kint in
         emit st (Try (op, r, x, y, slow));
         Hashtbl.replace made (op, x, y) (Ir.Reg r);
         Ir.Reg r)
  in
  let at (a, b) k = match b with Ir.Int 0 -> a | _ -> t Add a (t Mul k b) in
  let checked ab = ignore (at ab (Reg c)); ignore (at ab (Reg h)); Some ab in
  let invariant j = st.ver.tv.(j) == TI && (not (List.mem j written)) && plain st j && st.regs.(j) >= 0 in
  let rec affine (e : expr) =
    match e.e with
    | Lint n -> Some (Ir.Int n, Ir.Int 0)
    (* The loop's variable is its counter only when the body leaves it alone. *)
    | Var { b = Local j; _ } when j = i -> if List.mem i written then None else Some (Int 0, Int 1)
    | Var { b = Local j; _ } when invariant j -> Some (Reg st.regs.(j), Int 0)
    | Var { b = Cell { m; k; stable = true }; _ } -> (match st.w.modules.(m).cells.(k) with Int n -> Some (Int n, Int 0) | _ -> None)
    | Bin (((Add | Sub) as op), x, y) ->
      (match affine x, affine y with
       | Some (a1, b1), Some (a2, b2) ->
         let op = if op = Add then Ir.Add else Sub in
         checked (t op a1 a2, t op b1 b2)
       | _ -> None)
    | Bin (Mul, x, y) ->
      (match affine x, affine y with
       | Some (a1, Ir.Int 0), Some (a2, b2) | Some (a2, b2), Some (a1, Ir.Int 0) -> checked (t Mul a2 a1, t Mul b2 a1)
       | _ -> None)
    | Neg x -> (match affine x with Some (a, b) -> checked (t Sub (Int 0) a, t Sub (Int 0) b) | None -> None)
    | _ -> None
  in
  (* The indexes of float arrays read or written with one index, or one per dimension, in the whole body; for a loop with
     loops inside ([again]), outside their bodies, the bounds of their ranges included. *)
  let found = ref [] in
  let floats v n =
    st.arrays.(v) >= 0 && (let _, _, store, nd = Vec.get st.arr st.arrays.(v) in (store = 0 || store = 2) && (n = 1 || nd = n)) in
  let plain a = Array.for_all (function Ix _ -> true | All -> false) a in
  let exprs a = Array.map (function Ix x -> x | All -> assert false) a in
  let rec scan e =
    walk
      (fun (e : expr) ->
         match e.e with
         | Index ({ e = Var { b = Local v; _ }; _ }, a, false)
         | Set { root = { b = Local v; _ }; path = [| { sk = Sindex (a, false); _ } |]; _ } when plain a && floats v (Array.length a) ->
           found := (e.id, v, exprs a) :: !found;
           true
         | For { iter = { e = Range (x, y); _ }; _ } when again <> None -> scan x; scan y; false
         | Field _ | Struct_lit _ | For _ | While _ | Range _ -> false
         | _ -> true)
      e
  in
  Array.iter scan fbody;
  (* The indexes kept: each affine; in a loop with loops inside, only c + k, which needs no register of its own (below),
     for a k near 0, so that its 8 (k - 1) bytes of the cell's address are exact. *)
  let near = 1 lsl 20 in
  let form x = dry := true; let f = affine x in dry := false; f in
  let kept (_, _, xs) =
    match again, xs with
    | None, _ -> Array.for_all (fun x -> form x <> None) xs
    | Some _, [| x |] -> (match form x with Some (Ir.Int k, Ir.Int 1) -> abs k < near | _ -> false)
    | Some _, _ -> false
  in
  let found = List.filter kept !found in
  if again <> None && found = [] then (close st (Jump slow); false) else begin
  let table = Hashtbl.copy st.fast and steps = ref [] in
  (* An index c + k checked inside: then c and h are far from overflow, as k is near 0 and h + k at most a size. *)
  let bounded = ref false in
  let test cmp p q =
    if not (Hashtbl.mem tested (cmp, p, q)) then begin
      Hashtbl.replace tested (cmp, p, q) ();
      let next = block st in
      close st (Branch (cmp, Kint, p, q, slow, next));
      st.cur <- next
    end
  in
  (* An index inside [1, size] at both ends. The counter is at most its bound here, so a constant step orders the ends:
     the lower one against 1, the upper one against the size. *)
  let inside ab size =
    let first = at ab (Reg c) and last = at ab (Reg h) in
    (match snd ab with
     | Ir.Int k ->
       let lo, hi = if k >= 0 then first, last else last, first in
       test Lt lo (Int 1);
       test Gt hi size
     | _ ->
       test Lt first (Int 1);
       test Lt last (Int 1);
       test Gt first size;
       test Gt last size);
    first
  in
  (* Where an index is at the counter's turn, a register and cells after it: c + k is the counter and k cells, nothing
     to keep; any other a + b·c gets a register, moved by b at each turn. A run that comes back inside a loop with loops
     inside finds its counter in its slot, and nothing else of the checks: such a loop keeps only c + k. *)
  let regs = Hashtbl.create 8 in
  let index_reg ab first =
    match ab with
    | Ir.Int k, Ir.Int 1 when abs k < near -> c, k
    | _ ->
      (match Hashtbl.find_opt regs ab with
       | Some ix -> ix, 0
       | None ->
         let ix = reg st Kint in
         emit st (Move (ix, first));
         Hashtbl.replace regs ab ix;
         steps := (ix, snd ab) :: !steps;
         ix, 0)
  in
  (* The size of dimension [d] of array [a], or its cells for [d] = -1. *)
  let size a d =
    match Hashtbl.find_opt sizes (a, d) with
    | Some r -> Ir.Reg r
    | None ->
      let r = reg st Kint in
      emit st (if d < 0 then Len (r, a) else Dim (r, a, d));
      Hashtbl.replace sizes (a, d) r;
      Ir.Reg r
  in
  List.iter
    (fun (node, v, xs) ->
       let a = st.arrays.(v) in
       match Array.map affine xs with
       | [| Some ab |] ->
         let first = inside ab (size a (-1)) in
         let ix, k = index_reg ab first in
         if ix = c then bounded := true;
         Hashtbl.replace table node (a, ix, k)
       | abs when Array.for_all Option.is_some abs ->
         (* Each index inside its dimension at both ends: the cell, 1 + the sum of (index - 1) * stride, moves by the sum
            of each step times its stride. *)
         let cell = ref (Ir.Int 1, Ir.Int 0) and stride = ref (Ir.Int 1) in
         Array.iteri
           (fun d ab ->
              let ab = Option.get ab and n = size a d in
              ignore (inside ab n);
              let (a0, b0) = !cell in
              cell := (t Add a0 (t Mul (t Sub (fst ab) (Int 1)) !stride), t Add b0 (t Mul (snd ab) !stride));
              stride := t Mul !stride n)
           abs;
         let ix, k = index_reg !cell (at !cell (Reg c)) in
         Hashtbl.replace table node (a, ix, k)
       | _ -> ())
    found;
  (* Fuel for every step left, h - c + 1, unless the loop counts its steps as it goes: unchecked when bounded. *)
  if again = None then begin
    let n =
      if !bounded then begin
        let d = reg st Kint and n = reg st Kint in
        emit st (Op (Sub, d, Reg h, Reg c, -1));
        emit st (Op (Add, n, Reg d, Int 1, -1));
        Ir.Reg n
      end
      else t Add (t Sub (Reg h) (Reg c)) (Int 1)
    in
    let ok = block st in
    close st (Fuel_ge (n, ok, slow));
    st.cur <- ok
  end;
  let fbody_b = block st and finc = block st in
  goto st fbody_b;
  let r = var st i in
  if r <> c then emit st (Move (r, Reg c));
  let around = st.fast in
  st.fast <- table;
  loop_in st exit (fun () -> stmts st ~root fbody);
  st.fast <- around;
  (* A step proved before the loop, or a tick, as the loops inside count steps that nothing proved. *)
  (match again with
   | None -> emit st Burn
   | Some p ->
     (* The slow copy's tick: the same point, so that a run that leaves comes back the same way from either. *)
     emit st (Ir.Tick (p, outer st, -1));
     goto st (block st));
  (* Bounded, the counter's step can't overflow: the test at the bottom, one branch a turn; the variable then ends at
     its bound, as the interpreter's. *)
  if !bounded then begin
    emit st (Incr c);
    List.iter (fun (ix, step) -> emit st (Bump (ix, step))) !steps;
    let last = block st in
    close st (Branch (Le, Kint, Reg c, Reg h, fbody_b, last));
    st.cur <- last;
    emit st (Move (c, Reg h));
    close st (Jump exit)
  end
  else begin
    close st (Branch (Eq, Kint, Reg c, Reg h, exit, finc));
    st.cur <- finc;
    emit st (Incr c);
    List.iter (fun (ix, step) -> emit st (Bump (ix, step))) !steps;
    close st (Jump fbody_b)
  end;
  true
  end

and loop_in st exit f =
  st.loops <- exit :: st.loops;
  f ();
  st.loops <- List.tl st.loops

and hidden st =
  let r = reg st Kint in
  Vec.add_last st.hidden { reg = r; kind = Kint; slot = st.ver.frame + Vec.length st.hidden };
  r

(* The last expression of the body: its value is the result, and a self tail call loops. *)
and tail st (e : expr) =
  match e.e with
  | Return { rvalue = Some v; _ } -> tail st v
  | If (c, yes, no) ->
    let y = block st and n = block st in
    cond st c y n;
    st.cur <- y;
    assume st c true (fun () -> tail_block st yes);
    st.cur <- n;
    assume st c false (fun () -> tail_block st no)
  | Call ({ self_tail = true; _ } as call) when Array.length call.args = Array.length st.f.params ->
    let args = Array.map (fun (a : arg) -> if a.aname <> None then raise No else expr st a.value) call.args in
    let ps = Array.mapi (fun j (_ : param) -> var st j) st.f.params in
    (* The arguments first, then the parameters: an argument can read a parameter. *)
    let tmp =
      Array.mapi
        (fun j (x, xk) ->
           let k = Vec.get st.kinds ps.(j) in
           if xk <> k then raise No;
           let r = reg st k in
           emit st (Move (r, x));
           r)
        args
    in
    Array.iteri (fun j r -> emit st (Move (ps.(j), Reg r))) tmp;
    emit st (Ir.Tick (point st st.body, outer st, -1));
    close st (Jump st.body)
  | _ when st.vret <> None -> vgive st (vexpr st e)
  | _ -> result st (expr st e)

(* A value the body gives: of the kind of its version's result; inlined, where the version's result has no kind, of the
   kind of the first one it gives, which every other must have too. *)
and result st (x, xk) =
  match st.ret_to with
  | Some (-1, cont) ->
    let r = reg st xk in
    st.ret_to <- Some (r, cont);
    give st x
  | Some (r, _) when st.ver.ret != TI && st.ver.ret != TF -> if Vec.get st.kinds r <> xk then raise No else give st x
  | _ -> give st (convert st (kind_of st.ver.ret) (x, xk))

(* The end of a body: its result, or, inlined, the result in its register and on to the block after. *)
and give st v =
  match st.ret_to with
  | Some (r, cont) ->
    emit st (Move (r, v));
    close st (Jump cont)
  | None -> close st (Return v)

and tail_block st (b : block) =
  let n = Array.length b in
  if n = 0 then raise No;
  for j = 0 to n - 2 do if not st.dyn.dead then guarded st b.(j) done;
  if not st.dyn.dead then guarded ~last:true st b.(n - 1)

(* A statement where the region can't go on from, as one of an inlined body: when it doesn't lower and a guard could go
   back from here, the run goes back to the interpreter before the statement of the region's loop that holds it, as a
   failed guard does, and the rest of its block isn't made. *)
and guarded ?(last = false) st (x : expr) =
  let lower () = if last then tail st x else stmt st x in
  if st.dyn.bail = None || (last && st.ret_to = None) then lower ()
  else begin
    let undo = saved st in
    match lower () with
    | () -> ()
    | exception No ->
      undo ();
      let k = bail st in
      close st (Bail k);
      st.cur <- block st;
      st.dyn.dead <- true
  end

let rec func st name =
  let ver = st.ver and f = st.f in
  let entry = block st in
  st.cur <- entry;
  let body = block st in
  st.body <- body;
  ignore (tick st body);
  tail_block st (Lazy.force f.body);
  let var_of i = { Ir.reg = st.regs.(i); kind = Vec.get st.kinds st.regs.(i); slot = ver.map.(i) } in
  (* The parameters in registers, in order: a float array comes from its value slot instead. *)
  let params = List.filter_map (fun j -> if st.regs.(j) >= 0 then Some (var_of j) else None) (List.init (Array.length f.params) Fun.id) in
  let vars = List.filter_map (fun i -> if st.regs.(i) >= 0 then Some (var_of i) else None) (List.init f.nvars Fun.id) in
  finish st name ~params ~vars

and finish ?(numbers = []) ?(sunk = []) st name ~params ~vars =
  let ver = st.ver in
  let hidden = Vec.to_list st.hidden in
  let blocks = Vec.to_array st.blocks in
  Array.iter (fun (b : Ir.block) -> b.ins <- List.rev b.ins) blocks;
  let has p = Array.exists (fun (b : Ir.block) -> List.exists p b.ins) blocks in
  (* Small arrays in slots: only in the outermost frame of a region, the one frame that has its hidden slots. *)
  let vslots = st.dyn.vslots in
  if vslots > 0 && not st.region then raise No;
  let flag_slot i =
    match st.vecs.(i) with
    | Some { ro = true; _ } -> -2
    | _ -> if st.flags.(i) < 0 then -1 else (List.find (fun (v : Ir.var) -> v.reg = st.flags.(i)) hidden).slot
  in
  let n_hidden = List.length hidden in
  let vecs =
    List.filter_map
      (fun (i, v) -> match v with Some v when v.vslot >= 0 -> Some (ver.frame + n_hidden + v.slot, v.vslot, v.rows, v.cols, flag_slot i) | _ -> None)
      (List.mapi (fun i v -> i, v) (Array.to_list st.vecs))
  in
  let n_hidden = n_hidden + vslots in
  ( { Ir.name; params = Array.of_list params; result = (if st.region then Kint else kind_of ver.ret);
      vars = Array.of_list (vars @ hidden); arrays = Vec.to_array st.arr; kinds = Vec.to_array st.kinds; blocks;
      resumes = Vec.to_array st.resumes; frame = ver.frame;
      size = ver.frame + max n_hidden (Vec.length st.dyn.consts + 1) + 2; hidden = n_hidden;
      consts = Vec.to_array st.dyn.consts; restores = Vec.to_array st.dyn.restores;
      keeps = Vec.to_array st.dyn.keeps; loose = st.dyn.loose; sites = Array.make (Vec.length st.sites) (-1);
      pure = not (has (function Ir.Set_elem _ | Set_at _ | Put _ | Into _ -> true | _ -> false));
      calls = has (function Ir.Call _ | Enter _ -> true | _ -> false); chains = Vec.to_array st.chains;
      spills = st.w.hooks;
      stride = st.mem.(0); need = st.mem.(1); numbers = Array.of_list numbers; lent = Array.of_list st.dyn.lent;
      sunk = Array.of_list sunk; points = Vec.to_array st.dyn.points; vslots; vecs = Array.of_list vecs;
      cells = Array.of_list st.dyn.cells },
    Vec.to_array st.sites )

(* What the lowering of a region leaves out of what it looks at, from the statements of its branches that didn't lower
   before, [roots]: one that assigns a variable, and the rest of its block, which the interpreter makes after it. One
   that assigns none is made again, looked at, as a write into an array that a statement left out made one of the loop
   since: buf[used + 1] = t after the branch that makes buf anew. *)
let dead roots (loop : expr) =
  let out = ref [] in
  let assigns x = try assigned ~sets:false [] x <> [] with Unknown -> true in
  let rec block b =
    ignore
      (Array.fold_left
         (fun off (x : expr) ->
            let off = off || (List.mem x.id roots && assigns x) in
            if off then out := x.id :: !out else inner x;
            off)
         false b)
  and inner e = walk (fun (y : expr) -> match y.e with If (_, a, b) -> block a; block b; false | _ -> true) e in
  if roots <> [] then inner loop;
  !out

(* The local variables a loop names. *)
let locals ?cold acc e =
  let acc = ref acc in
  walk ?cold
    (fun (x : expr) ->
       match x.e with
       | Var { b = Local j; _ } | Assign ({ b = Local j; _ }, _) | For { var = { b = Local j; _ }; _ }
       | Set { root = { b = Local j; _ }; _ } -> acc := j :: !acc; true
       | Assign _ | For _ | Set _ -> false
       | _ -> true)
    e;
  !acc

(* The variables an iteration of a loop may read before it assigns them: those whose values go from one iteration to the
   next. A statement other than an assignment counts every variable it names. *)
let carried ?cold (loop : expr) =
  let body, first = match loop.e with For { fbody; _ } -> fbody, [] | While { cond; body; _ } -> body, locals [] cond | _ -> [||], [] in
  let set = ref [] in
  let before l = List.filter (fun j -> not (List.mem j !set)) l in
  Array.fold_left
    (fun acc (s : expr) ->
       match s.e with
       | _ when (match cold with Some c -> List.mem s.id c | None -> false) -> acc
       | Assign ({ b = Local j; _ }, v) ->
         let acc = before (locals [] v) @ acc in
         set := j :: !set;
         acc
       | _ -> before (locals ?cold [] s) @ acc)
    first body

(* Can variable [i] be a map the run never makes: assigned only by statements p = a[k] of the loop's body, [a] a list
   that [list] takes, and read only as p.Name. *)
let sinkable ?cold (loop : expr) i list =
  let body = match loop.e with For { fbody; _ } -> fbody | While { body; _ } -> body | _ -> [||] in
  let bad = ref false and sets = ref 0 in
  let check =
    walk ?cold (fun (x : expr) ->
        match x.e with
        | Field ({ e = Var { b = Local j; _ }; _ }, _) when j = i -> false
        | Var { b = Local j; _ } | Assign ({ b = Local j; _ }, _) | Set { root = { b = Local j; _ }; _ }
        | For { var = { b = Local j; _ }; _ } when j = i -> bad := true; false
        | _ -> true)
  in
  Array.iter
    (fun (s : expr) ->
       match s.e with
       | Assign ({ b = Local j; _ }, { e = Index ({ e = Var { b = Local a; _ }; _ }, [| Ix k |], false); _ }) when j = i && list a ->
         incr sets;
         check k
       | _ -> check s)
    body;
  (match loop.e with For { iter; _ } -> check iter | While { cond; _ } -> check cond | _ -> ());
  !sets > 0 && not !bad

(* Is every value the loop assigns to variable [i] a number by its form: arithmetic, a literal, a field of a map that
   [kept] says is kept as its floats, or a cell of an array that [cells] says holds numbers, floats or integers. A read
   of another list or a call can give another kind at each turn. *)
let numeric ?cold (loop : expr) i kept cells =
  let ok = ref true in
  (* An if gives a number by its form when each branch's value does, or is a variable, kept as a number or not. *)
  (* A variable copied, as s = e, is one too: if it holds another kind, the loop lowers again with [i] a value. *)
  let rec number (v : expr) =
    match v.e with
    | Bin ((Add | Sub | Mul | Div | Pow), _, _) | Neg _ | Lfloat _ | Lint _ | Var { b = Local _; _ } -> true
    | Field ({ e = Var { b = Local p; _ }; _ }, _) -> kept p
    | Index ({ e = Var { b = Local a; _ }; _ }, _, false) -> cells a
    | If (_, y, n) when Array.length y > 0 && Array.length n > 0 -> number y.(Array.length y - 1) && number n.(Array.length n - 1)
    | _ -> false
  in
  walk ?cold
    (fun (x : expr) ->
       (match x.e with
        | Assign ({ b = Local j; _ }, v) when j = i -> if not (number v) then ok := false
        | _ -> ());
       true)
    loop;
  !ok

(* A region's variables of any type that its loop names are values in registers; one it never assigns that holds an
   array of floats or of values now is an array, checked at each entry. A float array is one only where its loop names
   it: one the function makes after the loop has no value yet, and would fail the check of every entry. One whose value
   goes from an iteration to the next and holds an Int or a Float now is kept as that number for the whole run, unless
   [values] names it: an iteration then boxes and unboxes nothing. *)
let start ?(region = false) ?ctx ?scope ?(values = []) ?(cold = []) (w : world) unit index (ver : version) =
  let f = ver.owner.func in
  if ver.state <> 2 || ((not region) && Array.length f.captures > 0) then raise No;
  if (not region) && ver.ret != TI && ver.ret != TF then raise No;
  let kinds = Vec.create () in
  let regs = Array.make f.nvars (-1) and arrays = Array.make f.nvars (-1) and arr = Vec.create () in
  let np = Array.length f.params in
  let named = match scope with Some e -> locals ~cold [] e | None -> [] in
  let written = match scope with Some e -> (try Some (assigned ~sets:false ~cold [] e) with Unknown -> None) | None -> None in
  let plain i = (f.cell_of = [||] || f.cell_of.(i) < 0) && not f.maybe_undef.(i) in
  let crossing = match scope with Some e -> carried ~cold e | None -> [] in
  let spec = Array.make f.nvars false in
  (* A variable the loop assigns that holds a small array of floats now, of one or two dimensions: kept in slots. *)
  let vecs = Array.make f.nvars None and vs = ref 0 in
  (* One it never assigns nor writes is read from slots too, as the others it works with. *)
  let touched = match scope with Some e -> (try Some (assigned ~sets:true ~cold [] e) with Unknown -> None) | None -> None in
  let shape i =
    match ctx, written with
    | Some (ctx : ctx), Some l
      when (List.mem i l || match touched with Some t -> not (List.mem i t) | None -> false) && not (List.mem i values) ->
      (match ctx.v.(ctx.b + ver.map.(i)) with
       | Array { rows; cols; store = F _; dims = [||]; _ } when rows * cols >= 1 && rows * cols <= vmax -> Some (rows, cols)
       | _ -> None)
    | _ -> None
  in
  (* Every value the loop assigns to it is one by its form: a literal, an operation, a call, or a variable that holds
     such an array too. *)
  let vecish i =
    let ok = ref true in
    Option.iter
      (walk ~cold (fun (x : expr) ->
           (match x.e with
            | Assign ({ b = Local j; _ }, v) when j = i ->
              (match v.e with
               | Array_lit _ | Bin ((Add | Sub | Mul | Div), _, _) | Neg _ | Call _ -> ()
               | Var { b = Local k; _ } when shape k <> None -> ()
               | _ -> ok := false)
            (* Read with an index per dimension: an array of the loop, as before. *)
            | Index ({ e = Var { b = Local j; _ }; _ }, ixs, _) when j = i && Array.length ixs <> 1 -> ok := false
            | _ -> ());
           true))
      scope;
    !ok
  in
  let small i = if shape i <> None && vecish i then shape i else None in
  for i = 0 to f.nvars - 1 do
    match ver.tv.(i) with
    | TI | TF -> regs.(i) <- Vec.push kinds (kind_of ver.tv.(i))
    | (TA | TFA) when region && plain i && List.mem i named && small i <> None ->
      let rows, cols = Option.get (small i) in
      vecs.(i) <- Some { slot = !vs; n = rows * cols; rows; cols; vslot = ver.map.(i); ro = (match written with Some l -> not (List.mem i l) | None -> false) };
      vs := !vs + (rows * cols)
    | TFA when (if region then List.mem i named else i < np) && plain i -> arrays.(i) <- Vec.push arr (ver.map.(i), false, 0, 0)
    | TA when region && plain i && List.mem i named ->
      let store =
        match ctx, written with
        | Some (ctx : ctx), Some l when not (List.mem i l) ->
          (match ctx.v.(ctx.b + ver.map.(i)) with
           | Array { store = F _; _ } -> 0
           | Array { store = V _; _ } -> 1
           | Array { store = I _; _ } -> 2
           | _ -> -1)
        | _ -> -1
      in
      let number =
        match ctx with
        | Some (ctx : ctx) when List.mem i crossing && not (List.mem i values) ->
          (match ctx.v.(ctx.b + ver.map.(i)) with Int _ -> Some Ir.Kint | Float _ -> Some Kfloat | _ -> None)
        | _ -> None
      in
      if store >= 0 then arrays.(i) <- Vec.push arr (ver.map.(i), false, store, 0)
      else begin
        regs.(i) <- Vec.push kinds (Option.value number ~default:Ir.Kval);
        spec.(i) <- number <> None
      end
    | _ -> ()
  done;
  (* A map read from a list of values for its fields only, as a map of floats now: kept as its values. *)
  let sunk = Array.make f.nvars None in
  let values_list a = arrays.(a) >= 0 && (let _, _, store, _ = Vec.get arr arrays.(a) in store = 1) in
  (match scope, ctx with
   | Some loop, Some (ctx : ctx) ->
     for i = 0 to f.nvars - 1 do
       if regs.(i) >= 0 && ver.tv.(i) == TA && (not spec.(i)) && (not (List.mem i crossing)) && not (List.mem i values) then begin
         let sink n carrier =
           sunk.(i) <- Some { parts = Array.init n (fun _ -> Vec.push kinds Ir.Kfloat); carrier };
           regs.(i) <- -1
         in
         match ctx.v.(ctx.b + ver.map.(i)) with
         | Dict { keys = { deep = Flat; _ } as keys; vals = F _; _ } when Trie.is_whole keys && sinkable ~cold loop i values_list ->
           sink (Array.length keys.ks) (Dict { keys; vals = Trie.no_vals; d_owned = false })
         | Struct { shape; fields = F d; _ } when sinkable ~cold loop i values_list ->
           sink (Float.Array.length d) (Struct { shape; fields = Trie.no_vals; r_owned = false })
         | _ -> ()
       end
     done;
     let kept p = match sunk.(p) with Some { carrier = Dict _ | Struct _; _ } -> true | _ -> false in
     let cells a = arrays.(a) >= 0 && (match Vec.get arr arrays.(a) with _, _, (0 | 2), _ -> true | _ -> false) in
     for i = 0 to f.nvars - 1 do
       if regs.(i) >= 0 && ver.tv.(i) == TA && sunk.(i) = None && (not spec.(i)) && (not (List.mem i crossing))
          && (not (List.mem i values)) && numeric ~cold loop i kept cells then begin
         (* A number assigned in each turn before it is read, kept as one as a carried one is. *)
         let number k = regs.(i) <- Vec.push kinds k; spec.(i) <- true in
         match ctx.v.(ctx.b + ver.map.(i)) with
         | Float _ -> number Ir.Kfloat
         | Int _ -> number Kint
         | _ -> ()
       end
     done
   | _ -> ());
  (* A list whose maps no variable of the run holds: a write of a map of floats may go into the one it replaces. *)
  let inplace = Array.init f.nvars values_list in
  Option.iter
    (walk ~cold (fun (x : expr) ->
         (match x.e with
          | Assign ({ b = Local j; _ }, { e = Index ({ e = Var { b = Local a; _ }; _ }, _, _); _ }) when regs.(j) >= 0 -> inplace.(a) <- false
          | _ -> ());
         true))
    scope;
  { w; ver; f; index; kinds; blocks = Vec.create (); cur = 0; regs; arrays; arr; hidden = Vec.create ();
    resumes = Vec.create (); loops = []; sites = Vec.create (); live = Bytes.empty; unit; body = 0; region; infos = Vec.create ();
    fast = Hashtbl.create 1; twins = Hashtbl.create 8; ncalls = 0; chains = Vec.create (); inl = []; ret_to = None; mem = [| 0; 0 |]; ctx; spec; sunk; inplace;
    fixed = fixed_params f; resumable = false; cold; vecs; vret = None; flags = Array.make f.nvars (-1);
    dyn = { bail = None; dirty = false; callable = None; restores = Vec.create (); keeps = Vec.create (); loose = false; start = (0, 0);
            vars = []; need = None; consts = Vec.create (); known = []; nums = []; elems = []; lent = []; ticked = true; ranges = [];
            inside = []; points = Vec.create (); copies = (false, false); colds = []; dead = false; starts = []; vslots = !vs; cells = [] } }

(* Registers the sites of a lowered function, now that the whole unit lowered. *)
let register (w : world) (fn : Ir.func) (pos : (Pos.t * version * Bytes.t * bool) array) =
  let s = w.sites in
  Array.iteri
    (fun j (p, (ver : version), live, hidden) ->
       Vec.add_last s { sfile = ver.owner.file; spos = p; sfn = ver.owner.pname; sver = Some ver; soff = ver.frame;
                             slive = live; shidden = hidden };
       fn.sites.(j) <- Vec.length s - 1)
    pos

(* The unit whose first function [first] makes: then each version it calls, as whole functions. *)
let lower_unit ?ctx ?scope ?values ?cold (w : world) (ver : version) first =
  let u = { versions = Vec.create () } in
  Vec.add_last u.versions ver;
  let out = Vec.create () in
  match
    let st0 = start ~region:(first <> None) ?ctx ?scope ?values ?cold w u 0 ver in
    let extra = match first with Some f -> f st0 | None -> Vec.add_last out (func st0 "f0"); None in
    (match extra with Some fn -> Vec.add_last out fn | None -> ());
    let i = ref 1 in
    while !i < Vec.length u.versions do
      let v = Vec.get u.versions !i in
      let st = start w u !i v in
      Vec.add_last out (func st (Printf.sprintf "f%d" !i));
      incr i
    done
  with
  | () ->
    let fs = Vec.to_array out in
    Array.iter (fun (fn, pos) -> register w fn pos) fs;
    Some (Array.map fst fs)
  | exception No -> None
  | exception Unseen when ctx = None -> None

let unit (w : world) (ver : version) = lower_unit w ver None

(* A loop of a version, alone: it is entered at its start, its counter and bound already in their slots, or after the
   step of an iteration, and it ends at [Done] with every variable back in its slot. The first two hidden slots are its
   counter and bound, for a [for]. *)
let region ?ctx (w : world) (ver : version) (loop : expr) =
  let points = ref (0, 0) and infos = ref [||] and roots = ref [] in
  let make st =
    let crossing = carried ~cold:st.cold loop in
    Array.iteri
      (fun i _ ->
         let ro = match st.vecs.(i) with Some v -> v.ro | None -> false in
         if (st.spec.(i) || st.vecs.(i) <> None) && (not ro) && not (List.mem i crossing) then st.flags.(i) <- reg st Kint)
      st.flags;
    let entry = block st in
    st.cur <- entry;
    close st Done;
    (match loop.e with
     | For { var = { b = Local i; _ }; iter = { e = Range _; _ }; fbody; _ } ->
       let head = for_loop ~root:true st loop i fbody in
       close st Done;
       points := (point st head, 0)
     | While { cond = c; body; _ } ->
       let pre = block st and head = block st and inside = block st and exit = block st in
       st.cur <- pre;
       close st (Jump head);
       st.cur <- head;
       if allocates st body then reserve ~resume:pre st;
       (* A guard of the test goes back to the test: the interpreter's loop again. *)
       st.dyn.bail <- Some (-1);
       st.dyn.ticked <- false;
       cond st c inside exit;
       shows st;
       st.cur <- inside;
       loop_in st exit (fun () -> stmts st ~root:true body);
       let p = point st pre in
       emit st (Ir.Tick (p, true, -1));
       Vec.add_last st.infos (loop.id, -1, -1, p);
       close st (Jump head);
       st.cur <- exit;
       close st Done;
       points := (p, p)
     | _ -> raise No);
    let vars = List.filter_map (fun i -> if st.regs.(i) >= 0 && not st.spec.(i) then Some { Ir.reg = st.regs.(i); kind = Vec.get st.kinds st.regs.(i); slot = ver.map.(i) } else None)
        (List.init st.f.nvars Fun.id) in
    (* A variable kept as a number lives in a hidden slot of its stack while the run lasts; one a turn reads before it
       assigns it needs its value from the start. *)
    (* The flags of the variables a turn assigns before it reads them, in hidden slots of the int stack. *)
    Array.iter (fun r -> if r >= 0 then Vec.add_last st.hidden { Ir.reg = r; kind = Kint; slot = ver.frame + Vec.length st.hidden }) st.flags;
    let flag_of i = if st.flags.(i) < 0 then -1 else (List.find (fun (v : Ir.var) -> v.reg = st.flags.(i)) (Vec.to_list st.hidden)).slot in
    let numbers =
      List.filter_map
        (fun i ->
           if not st.spec.(i) then None
           else begin
             let v = { Ir.reg = st.regs.(i); kind = Vec.get st.kinds st.regs.(i); slot = ver.frame + Vec.length st.hidden } in
             Vec.add_last st.hidden v;
             Some (v, ver.map.(i), flag_of i)
           end)
        (List.init st.f.nvars Fun.id)
    in
    (* A map kept as its values: its values, in hidden float slots. *)
    let hide r = let v = { Ir.reg = r; kind = Kfloat; slot = ver.frame + Vec.length st.hidden } in Vec.add_last st.hidden v; v.slot in
    let sunk =
      List.filter_map
        (fun i -> match st.sunk.(i) with None -> None | Some s -> Some ((Array.map hide s.parts).(0), ver.map.(i), s.carrier))
        (List.init st.f.nvars Fun.id)
    in
    (* Statements found cold now: the loop lowers again when what it leaves out changes with them. *)
    let found = List.sort_uniq compare (st.dyn.colds @ !roots) in
    if dead found loop <> st.cold then raise (Cold found);
    infos := Vec.to_array st.infos;
    Some (finish ~numbers ~sunk st "f0" ~params:[] ~vars)
  in
  let rec go values cold tries =
    roots := cold;
    match lower_unit ?ctx ~scope:loop ~values ~cold:(dead cold loop) w ver (Some make) with
    | Some fns -> Some (fns, fst !points, !infos)
    | None -> None
    | exception Respec i -> go (i :: values) cold tries
    | exception Cold c when tries < 8 -> go values c (tries + 1)
    | exception Cold _ -> None
  in
  go [] [] 0
