open Types
open Ast

let join a b =
  if a == b then a
  else
    match a, b with
    | TBot, x | x, TBot -> x
    | _ -> TA

let make_version (p : proto) sg =
  let rec v =
    { owner = p; sg; ret = TBot; size = 0;
      rv = (fun ctx -> ctx.w.compile_ver ctx v; v.rv ctx);
      ri = (fun ctx -> ctx.w.compile_ver ctx v; v.ri ctx);
      rf = (fun ctx -> ctx.w.compile_ver ctx v; v.rf ctx);
      slots = [||]; state = 0; tv = [||]; tn = [||]; map = [||]; frame = 0; pk = [||]; call_off = 0 }
  in
  v

let generic_version (p : proto) =
  match p.generic with
  | Some v -> v
  | None ->
    let v = make_version p (Array.make (Array.length p.func.params) TA) in
    p.generic <- Some v;
    v

let max_versions = 8

let version_for w (p : proto) sg =
  if w.no_spec || Array.for_all (fun t -> t == TA) sg then generic_version p
  else
    match List.find_opt (fun v -> v.sg = sg) p.versions with
    | Some v -> v
    | None ->
      if List.length p.versions >= max_versions then generic_version p
      else begin
        let v = make_version p sg in
        p.versions <- v :: p.versions;
        v
      end

(* Arranges the arguments of a call by parameter, or gives the error. *)
let bind_args (f : func) (args : arg array) =
  let np = Array.length f.params in
  let out = Array.make np None in
  let error = ref None in
  let fail m = if !error = None then error := Some m in
  Array.iteri
    (fun i (a : arg) ->
       match a.aname with
       | None ->
         if i < np then out.(i) <- Some a.value
         else fail (Messages.too_many f.fname np (Array.length args))
       | Some name ->
         let found = ref (-1) in
         Array.iteri (fun k (p : param) -> if String.equal p.pname name then found := k) f.params;
         if !found < 0 then fail (Messages.unknown_arg f.fname name)
         else if out.(!found) <> None then fail (Messages.duplicate_arg f.fname name)
         else out.(!found) <- Some a.value)
    args;
  Array.iteri
    (fun k v ->
       if v = None && f.params.(k).default = None then fail (Messages.missing_arg f.fname f.params.(k).pname))
    out;
  match !error with
  | Some m -> Error m
  | None -> Ok out

let arith a b =
  match a, b with
  | TBot, _ | _, TBot -> TBot
  | TI, TI -> TI
  | TF, (TF | TI) | TI, TF -> TF
  | TFA, (TFA | TF | TI) | (TF | TI), TFA -> TFA
  | _ -> TA

let divide a b =
  match a, b with
  | TBot, _ | _, TBot -> TBot
  | (TI | TF), (TI | TF) -> TF
  | TFA, (TFA | TF | TI) | (TF | TI), TFA -> TFA
  | _ -> TA

type env = {
  w : world;
  ver : version;
  fn : func;
  tv : ty array;
  tn : ty array;
  mutable rett : ty;
  mutable changed : bool;
}

let set_var env i t =
  let n = join env.tv.(i) t in
  if n != env.tv.(i) then begin
    env.tv.(i) <- n;
    env.changed <- true
  end

(* An Int that a parameter of type Float receives is a Float there. *)
let as_param (fn : func) k t =
  match t, fn.params.(k).ptype with
  | TI, Some { tname = "Float"; tpkg = None; _ } -> TF
  | _ -> t

(* And one that a function of type Float gives: its callers see a Float. Otherwise a return type changes no inference. *)
let as_result (fn : func) t =
  match t, fn.ret with
  | TI, Some { tname = "Float"; tpkg = None; tbang = false; _ } -> TF
  | _ -> t

let rec run w (ver : version) =
  if ver.state = 0 then begin
    ver.state <- 1;
    let fn = ver.owner.func in
    let generic = w.no_spec || (match ver.owner.generic with Some g -> g == ver | None -> false) in
    if generic then begin
      ver.tv <- Array.make fn.nvars TA;
      ver.tn <- Array.make fn.nnodes TA;
      ver.ret <- TA
    end
    else analyze w ver fn;
    place w ver fn;
    ver.state <- 2
  end

and analyze w ver fn =
  let tv = Array.make fn.nvars TBot in
  let env = { w; ver; fn; tv; tn = Array.make fn.nnodes TBot; rett = TBot; changed = false } in
  Array.iter (fun (_, inner) -> tv.(inner) <- TA) fn.captures;
  Array.iteri (fun i u -> if u then tv.(i) <- TA) fn.maybe_undef;
  Array.iteri (fun i k -> if k >= 0 then tv.(i) <- TA) fn.cell_of;
  Array.iteri (fun k t -> if t != TBot then tv.(k) <- join tv.(k) (as_param fn k t)) ver.sg;
  ver.tv <- tv;
  ver.tn <- env.tn;
  let pass () =
    env.changed <- false;
    Array.iteri
      (fun k t ->
         if t == TBot then
           match fn.params.(k).default with
           | Some d -> set_var env k (as_param fn k (ty env d))
           | None -> ())
      ver.sg;
    let last = block env fn.body in
    let r = join (as_result fn (join env.rett last)) ver.ret in
    if r != ver.ret then begin
      ver.ret <- r;
      env.changed <- true
    end
  in
  let passes = ref 0 in
  pass ();
  incr passes;
  while env.changed do
    if !passes >= 8 then begin
      Array.fill tv 0 (Array.length tv) TA;
      ver.ret <- TA
    end;
    pass ();
    incr passes;
    if !passes > 9 then env.changed <- false
  done;
  (* What never got a type is A, then a last pass updates the nodes. *)
  let bot = Array.exists (fun t -> t == TBot) tv || ver.ret == TBot in
  Array.iteri (fun i t -> if t == TBot then tv.(i) <- TA) tv;
  if ver.ret == TBot then ver.ret <- TA;
  if bot then begin
    let saved = ver.ret in
    pass ();
    ver.ret <- saved
  end

and block env (b : block) =
  let t = ref TA in
  Array.iter (fun e -> t := ty env e) b;
  !t

and ty env (e : expr) : ty =
  let t =
    match e.e with
    | Lint _ -> TI
    | Lfloat _ -> TF
    | Var { b = Local i; _ } -> env.tv.(i)
    | Var { b = Cell { m; k; stable = true }; _ } ->
      (match env.w.modules.(m).cells.(k) with
       | Float _ -> TF
       | Int _ -> TI
       | _ -> TA)
    | Bin ((Add | Sub | Mul), a, b) ->
      let x = ty env a in
      let y = ty env b in
      arith x y
    | Bin (Div, a, b) ->
      let x = ty env a in
      let y = ty env b in
      divide x y
    | Bin (Pow, a, b) ->
      let x = ty env a in
      let y = ty env b in
      (match x, y, b.e with
       | TBot, _, _ | _, TBot, _ -> TBot
       | TI, TI, Lint n when n >= 0 -> TI
       | TF, (TF | TI), _ | TI, TF, _ -> TF
       | _ -> TA)
    | Neg a ->
      (match ty env a with
       | (TI | TF | TFA | TBot) as t -> t
       | TA -> TA)
    | If (c, a, b) ->
      ignore (ty env c);
      let x = block env a in
      let y = block env b in
      join x y
    | Assign ({ b = Local i; _ }, v) ->
      set_var env i (ty env v);
      TA
    | Set { root = { b = Local i; _ }; path; value } ->
      Resolve.children (fun x -> ignore (ty env x)) e;
      let simple =
        Array.length path = 1
        && (match path.(0).sk with
            | Sindex (ixs, _) -> Array.for_all (function Ix _ -> true | All -> false) ixs
            | Sfield _ -> false)
      in
      let t = env.tn.(value.id) in
      let keeps_fa = simple && (t == TF || t == TI || t == TBot) in
      if env.tv.(i) != TBot && not (env.tv.(i) == TFA && keeps_fa) then set_var env i TA
      else if env.tv.(i) == TBot then set_var env i TA;
      TA
    | For { var = { b = Local i; _ }; iter; fbody; _ } ->
      set_var env i (element env iter);
      ignore (block env fbody);
      TA
    | Comp { cbody; cvar = { b = Local i; _ }; csrc; cguard } ->
      set_var env i (element env csrc);
      ignore (ty env cbody);
      Option.iter (fun g -> ignore (ty env g)) cguard;
      TA
    | Destructure (pt, v) ->
      ignore (ty env v);
      pattern env pt;
      TA
    | Fn_def ({ b = Local i; _ }, _) ->
      set_var env i TA;
      TA
    | Match { arms; _ } ->
      Array.iter (fun a -> pattern env a.pt) arms;
      Resolve.children (fun x -> ignore (ty env x)) e;
      TA
    | Question a ->
      ignore (ty env a);
      env.rett <- join env.rett TA;
      TA
    | Return r ->
      let t = match r.rvalue with Some v -> ty env v | None -> TA in
      env.rett <- join env.rett t;
      TBot
    | Break -> TBot
    | Call call -> call_type env call
    | Index (b, ixs, _) ->
      let base = ty env b in
      let scalar =
        Array.for_all
          (function
            | Ix x -> ty env x == TI
            | All -> false)
          ixs
      in
      if base == TFA && scalar then TF else if base == TBot then TBot else TA
    | End_index -> TI
    | _ ->
      Resolve.children (fun x -> ignore (ty env x)) e;
      TA
  in
  env.tn.(e.id) <- t;
  t

and element env (iter : expr) =
  match iter.e with
  | Range (a, b) ->
    ignore (ty env a);
    ignore (ty env b);
    env.tn.(iter.id) <- TA;
    TI
  | _ ->
    (match ty env iter with
     | TFA -> TF
     | TBot -> TBot
     | _ -> TA)

and pattern env = function
  | Pname { b = Local i; _ } -> set_var env i TA
  | Pname _ | Pwild | Plit _ -> ()
  | Parray ps | Pcons { cargs = ps; _ } -> Array.iter (pattern env) ps
  | Pstruct fs -> Array.iter (fun (_, q) -> pattern env q) fs

and call_type env (call : call) =
  let w = env.w in
  let arg_types = Array.map (fun a -> ty env a.value) call.args in
  let callee =
    match call.callee.e with
    | Var { b = Cell { m; k; stable = true }; _ } -> Some w.modules.(m).cells.(k)
    | _ ->
      ignore (ty env call.callee);
      None
  in
  match callee with
  | Some (Native n) ->
    if Array.exists (fun t -> t == TBot) arg_types then TBot else n.ret_ty arg_types
  | Some (Fun { proto; env = [||] }) ->
    if Array.exists (fun t -> t == TBot) arg_types then TBot
    else (
      match bind_args proto.func call.args with
      | Error _ -> TA
      | Ok slots ->
        let sg = Array.map (function None -> TBot | Some (a : expr) -> env.tn.(a.id)) slots in
        let v = version_for w proto sg in
        if v == env.ver then v.ret
        else begin
          if v.state = 0 then run w v;
          if v.state = 2 then begin
            v.ret
          end
          else TA
        end)
  | _ -> TA

(* The slots: parameters first, in the stack of their type. *)
and place w ver fn =
  let tv = ver.tv in
  let map = Array.make fn.nvars 0 in
  let nv = ref 0 and nf = ref 0 and ni = ref 2 in
  for i = 0 to fn.nvars - 1 do
    match tv.(i) with
    | TI -> map.(i) <- !ni; incr ni
    | TF -> map.(i) <- !nf; incr nf
    | _ -> map.(i) <- !nv; incr nv
  done;
  ver.map <- map;
  ver.frame <- max !nv (max !nf !ni);
  ver.pk <-
    Array.init (Array.length fn.params) (fun k ->
        (map.(k) * 4) + (match tv.(k) with TI -> 1 | TF -> 2 | _ -> 0));
  if w.hooks then
    ver.slots <-
      Array.init fn.nvars (fun i ->
          { vname = fn.var_names.(i); sty = tv.(i); at = map.(i);
            cell = (if fn.cell_of = [||] then -1 else fn.cell_of.(i)) })
