open Types
open Ast

(* Anything outside what the JIT takes: the version or the loop stays interpreted. *)
exception No

(* A guess that needs a value the frame doesn't hold yet: the loop can be lowered again later. *)
exception Unseen

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
  mutable fast : (int, int * int) Hashtbl.t;  (* in a loop's fast copy: each index proved inside, its array, its register *)
  mutable ncalls : int;  (* calls lowered so far *)
  mem : int array;
      (* shared with inlined bodies, the interpreter's view of the function's calls: the highest base of one from its frame,
         and the largest frame called; -1 when a callee has no interpreter's code yet *)
  ctx : ctx option;  (* a region's frame as it is now, whose values guide the guesses *)
  dyn : dyn;  (* shared with inlined bodies *)
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
}

and unit_ = { versions : version Vec.t }

(* What a block may assign, or [Unknown] for a construct the walk doesn't follow: then nothing is taken as invariant. *)
exception Unknown

(* With [sets] false, a variable written only through a path, as a cell of it, isn't counted. *)
let rec assigned ?(sets = true) acc (e : expr) =
  let assigned = assigned ~sets in
  let blk acc b = Array.fold_left assigned acc b in
  let ixs acc a = Array.fold_left (fun acc -> function Ix x -> assigned acc x | All -> acc) acc a in
  match e.e with
  | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ | Var _ | Break | Hook _ -> acc
  | Field (x, _) -> assigned acc x
  | Struct_lit { sfields; _ } -> Array.fold_left (fun acc (_, v) -> assigned acc v) acc sfields
  | Assign ({ b = Local j; _ }, v) -> assigned (j :: acc) v
  | For { var = { b = Local j; _ }; iter; fbody; _ } -> blk (assigned (j :: acc) iter) fbody
  | While { cond; body; _ } -> blk (assigned acc cond) body
  | If (c, y, n) -> blk (blk (assigned acc c) y) n
  | Set { root = { b = Local j; _ }; path; value } ->
    let acc = if sets then j :: acc else acc in
    assigned (Array.fold_left (fun acc (st : step) -> match st.sk with Sindex (a, _) -> ixs acc a | Sfield _ -> acc) acc path) value
  | Return { rvalue = Some v; _ } -> assigned acc v
  | Bin (_, x, y) | And (x, y) | Or (x, y) | Range (x, y) -> assigned (assigned acc x) y
  | Neg x | Not x -> assigned acc x
  | Index (x, a, _) -> ixs (assigned acc x) a
  | Call c -> Array.fold_left (fun acc (a : arg) -> assigned acc a.value) (assigned acc c.callee) c.args
  | _ -> raise Unknown

let math = [ "Sqrt", "sqrt"; "Exp", "exp"; "Log", "log"; "Sin", "sin"; "Cos", "cos"; "Tan", "tan"; "Asin", "asin";
             "Acos", "acos"; "Atan", "atan" ]

let reg st k =
  Vec.add_last st.kinds k;
  Vec.length st.kinds - 1

let block st =
  Vec.add_last st.blocks { Ir.ins = []; term = Return (Int 0) };
  Vec.length st.blocks - 1

(* Something of the current statement shows: a guard can't send it back to the interpreter any more. *)
let shows st =
  st.dyn.bail <- None;
  st.dyn.callable <- None

(* Instructions are kept in reverse while a block is built. Steps forbid a guard after them, not a call, whose way back
   restores the fuel. *)
let emit st i =
  (match i with
   | Ir.Tick _ | Call _ | Enter _ -> st.dyn.bail <- None
   | Set_elem _ | Set_at _ | Put _ | Incr _ | Bump _ | Burn -> shows st
   | Move (r, x) ->
     let d = st.dyn in
     d.known <- List.filter (fun (_, m, _, _) -> m <> r) d.known;
     d.nums <- List.filter (fun (_, v, _, _) -> v <> r) d.nums;
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
let facts st b = List.filter (fun (x, _, _, _) -> x = b) st.dyn.known, List.filter (fun (x, _, _, _) -> x = b) st.dyn.nums

let carry st (k, n) l =
  st.dyn.known <- List.map (fun (_, m, c, a) -> (l, m, c, a)) k @ st.dyn.known;
  st.dyn.nums <- List.map (fun (_, v, h, r) -> (l, v, h, r)) n @ st.dyn.nums

(* After both branches of an [if], at [join]: what each knew at its end. *)
let meet st (k1, n1) (k2, n2) join =
  let k = List.filter (fun (_, m, c, a) -> List.exists (fun (_, m', c', a') -> m = m' && c = c' && a = a') k2) k1 in
  let n = List.filter (fun (_, v, h, r) -> List.exists (fun (_, v', h', r') -> v = v' && h = h' && r = r') n2) n1 in
  carry st (k, n) join

let goto st l =
  close st (Jump l);
  st.cur <- l

(* With a debugger, the outermost frame of a unit writes its variables back on an error; an inlined or called one keeps
   them in registers, and a stop shows none of its own. *)
let site st pos =
  Vec.add_last st.sites (pos, st.ver, (if st.inl = [] && st.index = 0 then st.live else Bytes.empty), st.inl <> [] || st.index > 0);
  Vec.add_last st.chains st.inl;
  Vec.length st.sites - 1

let point st l =
  Vec.add_last st.resumes l;
  Vec.length st.resumes - 1

(* A tick can leave the run only in no loop of the function, or as the tick of a loop in no other. *)
let outer st = st.loops = []

let tick st l =
  let p = point st l in
  emit st (Ir.Tick (p, outer st));
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

(* An instruction at the start of the current statement, put there once it is known to be needed. *)
let at_start st i =
  let b, n = st.dyn.start in
  let blk = Vec.get st.blocks b in
  let rec split k l = if k = 0 then [], l else match l with x :: r -> let a, c = split (k - 1) r in x :: a, c | [] -> [], [] in
  let later, earlier = split (List.length blk.ins - n) blk.ins in
  blk.ins <- later @ (i :: earlier)

(* The statement a failed guard goes back to, putting back the variables it assigned so far, or no lowering. Their copies
   at its start are made at the first such guard. *)
let bail st =
  match st.dyn.bail with
  | Some k when st.dyn.dirty ->
    if Vec.get st.dyn.restores k = [] && st.dyn.vars <> [] then
      Vec.set st.dyn.restores k
        (List.map
           (fun r ->
              let c = reg st (Vec.get st.kinds r) in
              at_start st (Ir.Move (c, Reg r));
              r, c)
           st.dyn.vars);
    Ir.restored + k
  | Some k -> k
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
       let j = Trie.index keys (Array.length vals) (Trie.hash key) key in
       if j >= 0 then Some vals.(j) else None
     | Some (Struct r) ->
       let j = Value.field_index r.shape name in
       if j >= 0 then Some r.fields.(j) else None
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
  let first = function
    | Dict { keys; _ } -> Some (`K keys)
    | Struct { shape; _ } -> Some (`S shape)
    | Fun { proto; _ } -> Some (`P proto)
    | _ -> None
  in
  let same a b =
    match first a, first b with
    | Some (`K x), Some (`K y) -> x == y
    | Some (`S x), Some (`S y) -> x == y
    | Some (`P x), Some (`P y) -> x == y
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

(* The function of the unit for a version, lowered later. *)
let callee st (v : version) =
  let vs = st.unit.versions in
  let rec find i = if i = Vec.length vs then (Vec.add_last vs v; i) else if Vec.get vs i == v then i else find (i + 1) in
  find 0

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
  | Bin (((Add | Sub | Mul) as op), a, b) ->
    let x = expr st a in
    let y = expr st b in
    let x, y = numbers st a b x y in
    (match snd x, snd y with
     | Kint, Kint ->
       let op = match op with Add -> Ir.Add | Sub -> Sub | _ -> Mul in
       fresh st Kint (fun r -> Op (op, r, fst x, fst y, site st e.pos))
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
    emit st (Move (r, convert st k (value_block st yes)));
    let end_yes = facts st st.cur in
    goto st join;
    carry st base n;
    st.cur <- n;
    emit st (Move (r, convert st k (value_block st no)));
    let end_no = facts st st.cur in
    goto st join;
    meet st end_yes end_no join;
    Reg r, k
  | Index (b, _, false) when Hashtbl.mem st.fast e.id ->
    let a, ix = Hashtbl.find st.fast e.id in
    ignore (array_of st b);
    fresh st Kfloat (fun r -> Elem_at (r, a, ix))
  | Index (b, [| Ix i |], false) ->
    let a = array_of st b in
    let _, _, store, _ = Vec.get st.arr a in
    (match guess st i (expr st i) with
     | x, Kint when store = 0 -> fresh st Kfloat (fun r -> Elem (r, a, x, site st e.pos))
     | x, Kint -> fresh st Kval (fun r -> Get (r, a, x, site st e.pos))
     | _ -> raise No)
  | Index (b, ixs, false) when Array.length ixs >= 2 ->
    let a = array_of st b in
    let q = cell st a (indexes st a ixs) e.pos false in
    let _, _, store, _ = Vec.get st.arr a in
    if store = 0 then fresh st Kfloat (fun r -> Elem_at (r, a, q)) else fresh st Kval (fun r -> Get (r, a, Reg q, site st e.pos))
  | Field (b, name) ->
    let v = (match expr st b with v, Kval -> v | _ -> raise No) in
    (match observe st b with
     | Some (Dict { keys = { deep = Flat; _ } as keys; vals; _ }) ->
       let key = Text name in
       let j = Trie.index keys (Array.length vals) (Trie.hash key) key in
       if j < 0 then unseen st;
       let c = const st (Dict { keys; vals = [||]; d_owned = false }) in
       let a = checked st v c (fun r -> Ir.Vals (r, v, c, bail st)) in
       (* Keys that grow in place can be held by a map of fewer values. *)
       let k = if Trie.is_whole keys then -1 else bail st in
       fresh st Kval (fun r -> Load (r, a, j, k))
     | Some (Struct { shape; _ }) ->
       let j = Value.field_index shape name in
       (* A small field of another package: the interpreter's error. *)
       if j < 0 || (shape.sm >= 0 && shape.sname <> None && (not (Lexer.is_public name))
                    && st.w.modules.(st.ver.owner.pm).host <> shape.sm) then raise No;
       let a = checked st v (-1 - shape.sid) (fun r -> Ir.Fields (r, v, shape.sid, bail st)) in
       fresh st Kval (fun r -> Load (r, a, j, -1))
     | Some _ -> raise No
     | None -> unseen st)
  | Struct_lit { sname; sfields } ->
    let names = Array.map fst sfields in
    let n = Array.length names in
    if n = 0 || n > Trie.width || List.length (List.sort_uniq String.compare (Array.to_list names)) < n then raise No;
    (* The same keys or shape as the interpreter's literal, so that both make the same maps. *)
    let carrier =
      match sname with
      | None -> Dict { keys = Compile.map_keys names; vals = [||]; d_owned = false }
      | Some _ ->
        let shape = Value.shape_of st.w ?sname ~m:st.w.modules.(st.ver.owner.pm).host names in
        Struct { shape; fields = [||]; r_owned = false }
    in
    let vals = Array.map (fun (_, v) -> stored st v) sfields in
    let c = const st carrier in
    alloc st (n + 5);
    fresh st Kval (fun r -> Record (r, (if sname = None then 8 else 4), c, vals))
  | Call call -> call_expr st e call
  | _ -> raise No

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
and stored st (e : expr) =
  match expr st e with
  | x, Kval ->
    (match e.e with Var _ | Index _ | Field _ -> emit st (Share x) | _ -> ());
    x
  | x -> box st x

(* While nothing of the statement showed but steps, a call that wants a longer stack bails: the interpreter makes it,
   with the fuel of the statement's start, kept there. Else such a call stops the run, which then must write nothing. *)
and back st =
  match st.dyn.callable with
  | Some k when not st.dyn.dirty ->
    if Vec.get st.dyn.keeps k = (-1, -1, -1) then begin
      let f = reg st Kint and sp = reg st Kint and q = reg st Kint in
      at_start st (Keep (f, sp, q));
      Vec.set st.dyn.keeps k (f, sp, q)
    end;
    k
  | _ ->
    st.dyn.loose <- true;
    -1

(* A small callee without a loop is lowered in place, one level deep: its frame is virtual, written only when an error or
   a limit unwinds through it, so traces and the limit of depth stay the interpreter's. *)
and inlinable (v : version) =
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
       | _ -> 1)
  in
  (v.ret == TI || v.ret == TF) && v.state = 2 && Array.length f.captures = 0 && (not f.has_self_tail)
  && blk_size size f.body <= 40

and blk_size size b = Array.fold_left (fun n x -> n + size x) 0 b

(* A call to [v] from the code of [st.ver]: where the interpreter would put its frame, and how much that frame takes. A
   version the interpreter hasn't compiled yet has no size: the limit of memory then counts native frames only. *)
and note st (v : version) =
  if v.size = 0 || st.mem.(0) < 0 then (st.mem.(0) <- -1; st.mem.(1) <- -1)
  else begin
    st.mem.(0) <- max st.mem.(0) st.ver.call_off;
    st.mem.(1) <- max st.mem.(1) v.size
  end

and inline st (e : expr) (v : version) args =
  let callsite = site st e.pos in
  let base = match st.inl with [] -> -1 | (vb, _, _) :: _ -> vb in
  let vb = reg st Kint in
  emit st (Frame (vb, base));
  emit st (Enter (vb, base, callsite, back st));
  let f = v.owner.func in
  let res = reg st (kind_of v.ret) and cont = block st in
  let child =
    { st with ver = v; f; regs = Array.make f.nvars (-1); arrays = Array.make f.nvars (-1); loops = [];
              inl = (vb, base, callsite) :: st.inl; ret_to = Some (res, cont); body = 0; region = false;
              fast = Hashtbl.create 1 }
  in
  for i = 0 to f.nvars - 1 do
    match v.tv.(i) with TI | TF -> child.regs.(i) <- reg st (kind_of v.tv.(i)) | _ -> ()
  done;
  Array.iteri
    (fun j x ->
       let r = child.regs.(j) in
       if r < 0 then raise No;
       emit child (Move (r, convert child (Vec.get st.kinds r) x)))
    args;
  (* The callee's step, as its frame's entry counts one. *)
  emit child (Ir.Tick (-1, false));
  tail_block child f.body;
  st.cur <- cont;
  st.ncalls <- child.ncalls + 1;
  Ir.Reg res, kind_of v.ret

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
       fresh st Kint (fun r -> Op ((if name = "Div" then Div else Mod), r, fst x, fst y, site st e.pos))
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
       let n = array_of st a.(0) in
       fresh st Kint (fun r -> Len (r, n))
     (* A struct's own function, whose fields take any value: its struct made here, after the step and the frame its
        call takes, checked as an inlined call's. *)
     | Fun { proto = { func = { body = [| { e = Return { rvalue = Some { e = Struct_lit { sname = Some _ as sname; sfields }; _ }; _ }; _ } |];
                                params; _ }; pm; arity; _ } as proto; env = [||] }
       when Array.for_all (fun (p : param) -> p.ptype = None && p.default = None) params && Array.length params = arity ->
       let vals = Array.map (stored st) (args_of call arity) in
       note st (Infer.version_for st.w proto (Array.make arity TA));
       let base = match st.inl with [] -> -1 | (vb, _, _) :: _ -> vb in
       let vb = reg st Kint in
       emit st (Frame (vb, base));
       emit st (Enter_or_bail (vb, bail st));
       emit st (Ir.Tick (-1, false));
       let shape = Value.shape_of st.w ?sname ~m:st.w.modules.(pm).host (Array.map fst sfields) in
       let c = const st (Struct { shape; fields = [||]; r_owned = false }) in
       alloc st (arity + 5);
       fresh st Kval (fun r -> Record (r, 4, c, vals))
     | Fun { proto; env = [||] } ->
       let a = args_of call proto.arity in
       if Array.exists (fun (p : param) -> p.default <> None) proto.func.params then raise No;
       let sg = Array.map (ty st) a in
       if Array.exists (fun t -> t != TI && t != TF) sg then raise No;
       (* The interpreter's direct call did the same, with the same types, when it compiled this version
          (Compile.prepare_call): this finds that version, it doesn't make one. *)
       let v = Infer.version_for st.w proto sg in
       if v.state = 0 then Infer.run st.w v;
       if v.state <> 2 || (v.ret != TI && v.ret != TF) then raise No;
       let vals = Array.map (expr st) a in
       let args = Array.map fst vals in
       let k = kind_of v.ret in
       note st v;
       if st.inl = [] && inlinable v then inline st e v vals
       else begin
         st.ncalls <- st.ncalls + 1;
         let back = back st in
         fresh st k (fun r -> Call (r, callee st v, args, site st e.pos, back))
       end
     | _ -> raise No)
  | Var { b = Local i; _ } when Vec.get st.kinds (var st i) = Ir.Kval -> call_value st e call (Ir.Reg (var st i))
  | _ -> raise No

(* A call of a function held in a value: a bet on the functions the interpreter saw this call reach, the last first, each
   tested in turn and called as a direct call is; any other goes back to the interpreter. This is the polymorphic inline
   cache of Hölzle, Chambers and Ungar (ECOOP 1991), its entries filled by the interpreter's type feedback. *)
and call_value st e (call : call) f =
  let seen = match List.assoc_opt e.id st.ver.seen with Some l -> !l | None -> [] in
  if seen = [] || List.length seen > Compile.seen_most then raise No;
  let n = Array.length call.args in
  let vals = Array.map (expr st) (args_of call n) in
  let targets = List.filter_map (fun p -> target st p vals) seen in
  if targets = [] then raise No;
  let k =
    match targets with
    | (_, (v : version)) :: rest when List.for_all (fun (_, (w : version)) -> w.ret == v.ret) rest -> kind_of v.ret
    | _ -> Ir.Kval
  in
  let r = reg st k and join = block st in
  let before = st.dyn.bail and clean = st.dyn.dirty in
  List.iter
    (fun (p, (v : version)) ->
       let yes = block st and next = block st in
       let c = const st (Fun { proto = p; env = [||] }) in
       close st (Is_fun (f, c, yes, next));
       st.cur <- yes;
       (* Each test runs after the ones before alone: a guard of its arguments may go back as the call's may. *)
       st.dyn.bail <- before;
       st.dyn.dirty <- clean;
       let args =
         Array.mapi
           (fun j (x, xk) ->
              match v.sg.(j), xk with
              | TI, Ir.Kval -> unbox st x Only_int
              | TF, Ir.Kval -> unbox st x Only_float
              | _ -> x, xk)
           vals
       in
       note st v;
       let res =
         if st.inl = [] && inlinable v then inline st e v args
         else begin
           st.ncalls <- st.ncalls + 1;
           let back = back st in
           fresh st (kind_of v.ret) (fun q -> Call (q, callee st v, Array.map fst args, site st e.pos, back))
         end
       in
       emit st (Move (r, if k = Ir.Kval then box st res else fst res));
       close st (Jump join);
       st.cur <- next)
    targets;
  st.dyn.bail <- before;
  st.dyn.dirty <- clean;
  close st (Bail (bail st));
  st.cur <- join;
  st.dyn.bail <- None;
  Ir.Reg r, k

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

and stmt st (e : expr) =
  match e.e with
  | Assign ({ b = Local i; _ }, v) ->
    let r = var st i in
    let x = (match Vec.get st.kinds r with Kval -> stored st v | k -> convert st k (expr st v)) in
    emit st (Move (r, x));
    (* An inlined callee's variables are its own: the way back has nothing of them to put back. *)
    if st.inl = [] then st.dyn.dirty <- true
  | Set { root = { b = Local i; _ }; path = [| { sk = Sindex (_, false); _ } |]; value }
    when st.arrays.(i) >= 0 && Hashtbl.mem st.fast e.id ->
    let a, ix = Hashtbl.find st.fast e.id in
    let x = to_float st (expr st value) in
    emit st (Set_at (a, ix, x))
  | Set { root = { b = Local i; _ }; path = [| { sk = Sindex ([| Ix ix |], false); sp } |]; value } when st.arrays.(i) >= 0 ->
    let a = st.arrays.(i) in
    let k = (match guess st ix (expr st ix) with x, Kint -> x | _ -> raise No) in
    let slot, _, store, nd = Vec.get st.arr a in
    (* As the interpreter's write: the index, then the value, then the array, which an F store takes only as a number. *)
    let x = if store = 0 then to_float st (expr st value) else stored st value in
    Vec.set st.arr a (slot, true, store, nd);
    (* At the step, as the interpreter names an index outside the array. *)
    emit st (if store = 0 then Set_elem (a, k, x, site st sp) else Put (a, k, x, site st sp))
  | Set { root = { b = Local i; _ }; path = [| { sk = Sindex (ixs, false); sp } |]; value }
    when st.arrays.(i) >= 0 && Array.length ixs >= 2 ->
    let a = st.arrays.(i) in
    let xs = indexes st a ixs in
    let x = (let _, _, store, _ = Vec.get st.arr a in if store = 0 then to_float st (expr st value) else stored st value) in
    let slot, _, store, nd = Vec.get st.arr a in
    Vec.set st.arr a (slot, true, store, nd);
    let q = cell st a xs sp true in
    emit st (if store = 0 then Set_at (a, q, x) else Put (a, Reg q, x, site st sp))
  | For { var = { b = Local i; _ }; iter = { e = Range (a, b); _ }; fbody; _ } ->
    let lo = expr st a in
    let hi = expr st b in
    if snd lo <> Kint || snd hi <> Kint then raise No;
    inner_loop st (fun () -> ignore (for_loop ~lo:(fst lo, fst hi) st e i fbody))
  | While { cond = c; body; _ } ->
    inner_loop st (fun () ->
        let head = block st and inside = block st and exit = block st in
        goto st head;
        cond st c inside exit;
        st.cur <- inside;
        if allocates st body then reserve st;
        loop_in st exit (fun () -> Array.iter (stmt st) body);
        let p = point st head in
        emit st (Ir.Tick (p, outer st));
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
    let before = st.dyn.bail and clean = st.dyn.dirty in
    carry st base y;
    st.cur <- y;
    Array.iter (stmt st) yes;
    let end_yes = facts st st.cur in
    goto st join;
    let after_yes = st.dyn.bail and dirty_yes = st.dyn.dirty in
    st.dyn.bail <- before;
    st.dyn.dirty <- clean;
    carry st base n;
    st.cur <- n;
    Array.iter (stmt st) no;
    let end_no = facts st st.cur in
    goto st join;
    meet st end_yes end_no join;
    if after_yes = None then shows st;
    st.dyn.dirty <- st.dyn.dirty || dirty_yes
  | Break ->
    (match st.loops with
     | l :: _ ->
       close st (Jump l);
       st.cur <- block st
     | [] -> raise No)
  | Return { rvalue = Some v; _ } ->
    let k = kind_of st.ver.ret in
    let x = convert st k (expr st v) in
    if st.region && st.ret_to = None then close st (Out x) else give st x;
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
  let around = st.dyn.need in
  st.dyn.need <- None;
  f ();
  st.dyn.need <- None;
  if around <> None then reserve st

(* Room for the allocations of a loop's step, checked once at its top, a resume point: there, when the young heap lacks it,
   the run leaves and comes back once the interpreter's allocation collected. *)
and reserve st =
  let l = block st in
  goto st l;
  let need = ref 0 in
  emit st (Reserve (need, point st l));
  st.dyn.need <- Some need

(* Can these statements allocate, outside the loops inside them: a map or struct made, a number stored as a value. *)
and allocates st (b : block) =
  let rec made (e : expr) =
    match e.e with
    | Struct_lit _ -> true
    | Bin (_, x, y) | And (x, y) | Or (x, y) -> made x || made y
    | Neg x | Not x | Field (x, _) -> made x
    | If (c, y, n) -> made c || Array.exists made y || Array.exists made n
    | Index (x, a, _) -> made x || Array.exists (function Ix i -> made i | All -> false) a
    | Call c ->
      (match c.callee.e with
       | Var { b = Cell { m; k; stable = true }; _ } ->
         (match st.w.modules.(m).cells.(k) with Fun { proto; _ } -> Resolve.struct_fields proto.func <> None | _ -> false)
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
    Array.iteri
      (fun k x ->
         (* The variables the statement may assign, whose copies the way back may need, made at its start. *)
         let vars = try List.sort_uniq compare (assigned ~sets:false [] x) with Unknown -> [] in
         st.dyn.vars <- List.filter (fun r -> r >= 0) (List.map (fun i -> st.regs.(i)) vars);
         st.dyn.start <- (st.cur, List.length (Vec.get st.blocks st.cur).ins);
         while Vec.length st.dyn.restores <= k do Vec.add_last st.dyn.restores [] done;
         while Vec.length st.dyn.keeps <= k do Vec.add_last st.dyn.keeps (-1, -1, -1) done;
         st.dyn.bail <- Some k;
         st.dyn.callable <- Some k;
         st.dyn.dirty <- false;
         stmt st x)
      b;
    shows st
  end else Array.iter (stmt st) b

(* A [for] over a..b. The counter is the loop's variable itself when the body leaves it alone, else a hidden slot; the
   bound is a hidden slot. With [lo] given, they start at it and at the bound; else they are in their slots (a region's
   loop). An innermost loop, with no loop and no call inside, also gets a fast copy, taken when, before it starts, the
   fuel covers all its steps and each index that is a + b·counter is proved inside its array at both ends, every part of
   it without overflow: that copy checks neither, and moves those indexes by their step. The checked copy runs
   otherwise, and is where the loop comes back after leaving. Gives the block that tests the counter. *)
and for_loop ?lo ?(root = false) st (e : expr) i fbody =
  let r = var st i in
  if Vec.get st.kinds r <> Kint then raise No;
  let written = try Some (Array.fold_left assigned [] fbody) with Unknown -> None in
  let own = match written with Some l -> not (List.mem i l) | None -> false in
  let c = if own then r else hidden st in
  let cslot = if own then st.ver.map.(i) else (Vec.get_last st.hidden).slot in
  let h = hidden st in
  let hslot = (Vec.get_last st.hidden).slot in
  let head = block st and decide = block st and body = block st and next = block st and inc = block st and exit = block st in
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
  let points = Vec.length st.resumes and calls = st.ncalls in
  if allocates st fbody then reserve st;
  if not own then emit st (Move (r, Reg c));
  loop_in st exit (fun () -> stmts st ~root fbody);
  let inner = Vec.length st.resumes = points && st.ncalls = calls in
  Vec.add_last st.infos (e.id, cslot, hslot, tick st next);
  close st (Branch (Eq, Kint, Reg c, Reg h, exit, inc));
  st.cur <- inc;
  emit st (Incr c);
  close st (Jump body);
  st.cur <- decide;
  (match written with
   | Some written when inner -> fast_copy st e i c h fbody written ~root ~slow:body ~exit
   | _ -> close st (Jump body));
  st.cur <- exit;
  head

and fast_copy st _e i c h fbody written ~root ~slow ~exit =
  (* The checks before the loop run one after the other, each block after the one before: an operation, a size or a test
     made once serves every index after it. *)
  let made = Hashtbl.create 16 and sizes = Hashtbl.create 8 and tested = Hashtbl.create 16 in
  let t op x y =
    match op, x, y with
    | (Ir.Add | Sub), _, Ir.Int 0 -> x
    | Add, Ir.Int 0, _ -> y
    | Mul, _, Ir.Int 0 | Mul, Ir.Int 0, _ -> Int 0
    | Mul, _, Ir.Int 1 -> x
    | Mul, Ir.Int 1, _ -> y
    | (Add | Sub | Mul), Ir.Int p, Ir.Int q when abs p < 1 lsl 30 && abs q < 1 lsl 30 ->
      Int (match op with Add -> p + q | Sub -> p - q | _ -> p * q)
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
  (* The indexes of float arrays read or written with one index, or one per dimension, in the whole body. *)
  let found = ref [] in
  let floats v n =
    st.arrays.(v) >= 0 && (let _, _, store, nd = Vec.get st.arr st.arrays.(v) in store = 0 && (n = 1 || nd = n)) in
  let plain a = Array.for_all (function Ix _ -> true | All -> false) a in
  let exprs a = Array.map (function Ix x -> x | All -> assert false) a in
  let rec walk (e : expr) =
    let blk b = Array.iter walk b in
    let ixs a = Array.iter (function Ix x -> walk x | All -> ()) a in
    (match e.e with
     | Index ({ e = Var { b = Local v; _ }; _ }, a, false) when plain a && floats v (Array.length a) ->
       found := (e.id, v, exprs a) :: !found
     | Set { root = { b = Local v; _ }; path = [| { sk = Sindex (a, false); _ } |]; _ } when plain a && floats v (Array.length a) ->
       found := (e.id, v, exprs a) :: !found
     | _ -> ());
    match e.e with
    | Assign (_, v) | Neg v | Not v | Return { rvalue = Some v; _ } -> walk v
    | Bin (_, x, y) | And (x, y) | Or (x, y) -> walk x; walk y
    | If (x, y, n) -> walk x; blk y; blk n
    | Set { value; path; _ } -> walk value; Array.iter (fun (s : step) -> match s.sk with Sindex (a, _) -> ixs a | Sfield _ -> ()) path
    | Index (x, a, _) -> walk x; ixs a
    | Call call -> Array.iter (fun (a : arg) -> walk a.value) call.args
    | _ -> ()
  in
  Array.iter walk fbody;
  (* Fuel for every step left: h - c + 1. *)
  let n = t Add (t Sub (Reg h) (Reg c)) (Int 1) in
  let ok = block st in
  close st (Fuel_ge (n, ok, slow));
  st.cur <- ok;
  let table = Hashtbl.create 8 and steps = ref [] in
  let test cmp p q =
    if not (Hashtbl.mem tested (cmp, p, q)) then begin
      Hashtbl.replace tested (cmp, p, q) ();
      let next = block st in
      close st (Branch (cmp, Kint, p, q, slow, next));
      st.cur <- next
    end
  in
  (* An index inside [1, size] at both ends. *)
  let inside ab size =
    let first = at ab (Reg c) and last = at ab (Reg h) in
    test Lt first (Int 1);
    test Lt last (Int 1);
    test Gt first size;
    test Gt last size;
    first
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
         let ix = reg st Kint in
         emit st (Move (ix, first));
         Hashtbl.replace table node (a, ix);
         steps := (ix, snd ab) :: !steps
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
         let ix = reg st Kint in
         emit st (Move (ix, at !cell (Reg c)));
         Hashtbl.replace table node (a, ix);
         steps := (ix, snd !cell) :: !steps
       | _ -> ())
    !found;
  let fbody_b = block st and finc = block st in
  goto st fbody_b;
  let r = var st i in
  if r <> c then emit st (Move (r, Reg c));
  st.fast <- table;
  loop_in st exit (fun () -> stmts st ~root fbody);
  st.fast <- Hashtbl.create 1;
  emit st Burn;
  close st (Branch (Eq, Kint, Reg c, Reg h, exit, finc));
  st.cur <- finc;
  emit st (Incr c);
  List.iter (fun (ix, step) -> emit st (Bump (ix, step))) !steps;
  close st (Jump fbody_b)

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
  let k = kind_of st.ver.ret in
  match e.e with
  | Return { rvalue = Some v; _ } -> tail st v
  | If (c, yes, no) ->
    let y = block st and n = block st in
    cond st c y n;
    st.cur <- y;
    tail_block st yes;
    st.cur <- n;
    tail_block st no
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
    emit st (Ir.Tick (point st st.body, outer st));
    close st (Jump st.body)
  | _ -> give st (convert st k (expr st e))

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
  for j = 0 to n - 2 do stmt st b.(j) done;
  tail st b.(n - 1)

let rec func st name =
  let ver = st.ver and f = st.f in
  let entry = block st in
  st.cur <- entry;
  let body = block st in
  st.body <- body;
  ignore (tick st body);
  tail_block st f.body;
  let var_of i = { Ir.reg = st.regs.(i); kind = Vec.get st.kinds st.regs.(i); slot = ver.map.(i) } in
  (* The parameters in registers, in order: a float array comes from its value slot instead. *)
  let params = List.filter_map (fun j -> if st.regs.(j) >= 0 then Some (var_of j) else None) (List.init (Array.length f.params) Fun.id) in
  let vars = List.filter_map (fun i -> if st.regs.(i) >= 0 then Some (var_of i) else None) (List.init f.nvars Fun.id) in
  finish st name ~params ~vars

and finish st name ~params ~vars =
  let ver = st.ver in
  let hidden = Vec.to_list st.hidden in
  let blocks = Vec.to_array st.blocks in
  Array.iter (fun (b : Ir.block) -> b.ins <- List.rev b.ins) blocks;
  let has p = Array.exists (fun (b : Ir.block) -> List.exists p b.ins) blocks in
  let n_hidden = List.length hidden in
  ( { Ir.name; params = Array.of_list params; result = (if st.region then Kint else kind_of ver.ret);
      vars = Array.of_list (vars @ hidden); arrays = Vec.to_array st.arr; kinds = Vec.to_array st.kinds; blocks;
      resumes = Vec.to_array st.resumes; frame = ver.frame;
      size = ver.frame + max n_hidden (Vec.length st.dyn.consts) + 2; hidden = n_hidden;
      consts = Vec.to_array st.dyn.consts; restores = Vec.to_array st.dyn.restores;
      keeps = Vec.to_array st.dyn.keeps; loose = st.dyn.loose; sites = Array.make (Vec.length st.sites) (-1);
      pure = not (has (function Ir.Set_elem _ | Set_at _ | Put _ -> true | _ -> false));
      calls = has (function Ir.Call _ | Enter _ -> true | _ -> false); chains = Vec.to_array st.chains;
      spills = st.w.hooks;
      stride = st.mem.(0); need = st.mem.(1) },
    Vec.to_array st.sites )

(* The local variables a loop names. *)
let rec locals acc (e : expr) =
  let blk acc b = Array.fold_left locals acc b in
  let ixs acc a = Array.fold_left (fun acc -> function Ix x -> locals acc x | All -> acc) acc a in
  match e.e with
  | Var { b = Local j; _ } -> j :: acc
  | Assign ({ b = Local j; _ }, v) -> locals (j :: acc) v
  | For { var = { b = Local j; _ }; iter; fbody; _ } -> blk (locals (j :: acc) iter) fbody
  | While { cond; body; _ } -> blk (locals acc cond) body
  | If (c, y, n) -> blk (blk (locals acc c) y) n
  | Set { root = { b = Local j; _ }; path; value } ->
    locals (Array.fold_left (fun acc (st : step) -> match st.sk with Sindex (a, _) -> ixs acc a | Sfield _ -> acc) (j :: acc) path) value
  | Return { rvalue = Some v; _ } -> locals acc v
  | Bin (_, x, y) | And (x, y) | Or (x, y) | Range (x, y) -> locals (locals acc x) y
  | Neg x | Not x | Field (x, _) -> locals acc x
  | Index (x, a, _) -> ixs (locals acc x) a
  | Call c -> Array.fold_left (fun acc (a : arg) -> locals acc a.value) (locals acc c.callee) c.args
  | Struct_lit { sfields; _ } -> Array.fold_left (fun acc (_, v) -> locals acc v) acc sfields
  | _ -> acc

(* A region's variables of any type that its loop names are values in registers; one it never assigns that holds an
   array of floats or of values now is an array, checked at each entry. A float array is one only where its loop names
   it: one the function makes after the loop has no value yet, and would fail the check of every entry. *)
let start ?(region = false) ?ctx ?scope (w : world) unit index (ver : version) =
  let f = ver.owner.func in
  if ver.state <> 2 || ((not region) && Array.length f.captures > 0) then raise No;
  if (not region) && ver.ret != TI && ver.ret != TF then raise No;
  let kinds = Vec.create () in
  let regs = Array.make f.nvars (-1) and arrays = Array.make f.nvars (-1) and arr = Vec.create () in
  let np = Array.length f.params in
  let named = match scope with Some e -> locals [] e | None -> [] in
  let written = match scope with Some e -> (try Some (assigned ~sets:false [] e) with Unknown -> None) | None -> None in
  let plain i = (f.cell_of = [||] || f.cell_of.(i) < 0) && not f.maybe_undef.(i) in
  for i = 0 to f.nvars - 1 do
    match ver.tv.(i) with
    | TI | TF ->
      Vec.add_last kinds (kind_of ver.tv.(i));
      regs.(i) <- Vec.length kinds - 1
    | TFA when (if region then List.mem i named else i < np) && plain i ->
      Vec.add_last arr (ver.map.(i), false, 0, 0);
      arrays.(i) <- Vec.length arr - 1
    | TA when region && plain i && List.mem i named ->
      let store =
        match ctx, written with
        | Some (ctx : ctx), Some l when not (List.mem i l) ->
          (match ctx.v.(ctx.b + ver.map.(i)) with Array { store = F _; _ } -> 0 | Array { store = V _; _ } -> 1 | _ -> -1)
        | _ -> -1
      in
      if store >= 0 then begin
        Vec.add_last arr (ver.map.(i), false, store, 0);
        arrays.(i) <- Vec.length arr - 1
      end else begin
        Vec.add_last kinds Ir.Kval;
        regs.(i) <- Vec.length kinds - 1
      end
    | _ -> ()
  done;
  { w; ver; f; index; kinds; blocks = Vec.create (); cur = 0; regs; arrays; arr; hidden = Vec.create ();
    resumes = Vec.create (); loops = []; sites = Vec.create (); live = Bytes.empty; unit; body = 0; region; infos = Vec.create ();
    fast = Hashtbl.create 1; ncalls = 0; chains = Vec.create (); inl = []; ret_to = None; mem = [| 0; 0 |]; ctx;
    dyn = { bail = None; dirty = false; callable = None; restores = Vec.create (); keeps = Vec.create (); loose = false; start = (0, 0);
            vars = []; need = None; consts = Vec.create (); known = []; nums = [] } }

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
let lower_unit ?ctx ?scope (w : world) (ver : version) first =
  let u = { versions = Vec.create () } in
  Vec.add_last u.versions ver;
  let out = Vec.create () in
  match
    let st0 = start ~region:(first <> None) ?ctx ?scope w u 0 ver in
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
  let points = ref (0, 0) and infos = ref [||] in
  let make st =
    let entry = block st in
    st.cur <- entry;
    close st Done;
    (match loop.e with
     | For { var = { b = Local i; _ }; iter = { e = Range _; _ }; fbody; _ } ->
       let head = for_loop ~root:true st loop i fbody in
       close st Done;
       points := (point st head, 0)
     | While { cond = c; body; _ } ->
       let head = block st and inside = block st and exit = block st in
       st.cur <- head;
       (* A guard of the test goes back to the test: the interpreter's loop again. *)
       st.dyn.bail <- Some (-1);
       cond st c inside exit;
       shows st;
       st.cur <- inside;
       if allocates st body then reserve st;
       loop_in st exit (fun () -> stmts st ~root:true body);
       let p = point st head in
       emit st (Ir.Tick (p, true));
       Vec.add_last st.infos (loop.id, -1, -1, p);
       close st (Jump head);
       st.cur <- exit;
       close st Done;
       points := (p, p)
     | _ -> raise No);
    let vars = List.filter_map (fun i -> if st.regs.(i) >= 0 then Some { Ir.reg = st.regs.(i); kind = Vec.get st.kinds st.regs.(i); slot = ver.map.(i) } else None)
        (List.init st.f.nvars Fun.id) in
    infos := Vec.to_array st.infos;
    Some (finish st "f0" ~params:[] ~vars)
  in
  match lower_unit ?ctx ~scope:loop w ver (Some make) with
  | Some fns -> Some (fns, fst !points, !infos)
  | None -> None
