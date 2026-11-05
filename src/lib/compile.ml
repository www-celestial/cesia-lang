open Types
open Ast

exception Break_loop
exception Return_value of t
exception Bad_arg of Messages.t

type c = {
  w : world;
  file : int;
  fn : string;
  func : func;
  ver : version;
  tv : ty array;  (* the type of each variable *)
  tn : ty array;  (* the type of each node *)
  map : int array;  (* the slot of each variable *)
  mutable off : int;  (* offset of the next call site *)
  mutable top : int;  (* the frame size needed *)
  mutable ends : (int * int * int) list;  (* for [end]: slot of the indexed array, dimension, number of indexes *)
  mutable live : Bytes.t;  (* the last compiled hook: what is assigned at this statement *)
}

let ty c (e : expr) = c.tn.(e.id)

let cell_of c i = if c.func.cell_of = [||] then -1 else c.func.cell_of.(i)

let[@inline never] not_int ctx v =
  Runtime.fail ctx Type (Messages.want_int "This value" (Value.describe v))

let[@inline never] not_float ctx v =
  Runtime.fail ctx Type (Messages.need_number "This value" (Value.describe v))

let[@inline] to_i ctx v =
  match v with
  | Int i -> i
  | _ -> not_int ctx v

let[@inline] to_f ctx v =
  match v with
  | Float x -> x
  | Int i -> float_of_int i
  | _ -> not_float ctx v

open struct
  let[@inline] add_i ctx s x y = Super.add_i ctx s x y
  let[@inline] sub_i ctx s x y = Super.sub_i ctx s x y
  let[@inline] mul_i ctx s x y = Super.mul_i ctx s x y
end

let[@inline] fget (ctx : ctx) k = Float.Array.get ctx.f (ctx.b + k)
let[@inline] iget (ctx : ctx) k = ctx.i.(ctx.b + k)

let site c pos =
  let s = c.w.sites in
  Dynarray.add_last s { sfile = c.file; spos = pos; sfn = c.fn; sver = Some c.ver; soff = c.off; slive = c.live };
  Dynarray.length s - 1

(* One step. [off]: beyond b + off, the v stack is dead. *)
let[@inline] tick ctx off =
  let f = ctx.fuel - 1 in
  ctx.fuel <- f;
  if f < 0 then Runtime.checkpoint ctx (ctx.b + off)

let[@inline] truth s ctx v =
  match v with
  | True -> true
  | False -> false
  | _ ->
    ctx.site <- s;
    Runtime.fail ctx Type (Messages.condition (Value.describe v))

(* The fast paths of generic arithmetic. The slow case knows its site. *)
let[@inline] add_a ctx s p q =
  match p, q with
  | Float u, Float w -> Float (u +. w)
  | Int u, Int w ->
    let r = u + w in
    if (u lxor r) land (w lxor r) < 0 then begin
      ctx.site <- s;
      Arith.add ctx p q
    end else Int r
  | Float u, Int w -> Float (u +. float_of_int w)
  | Int u, Float w -> Float (float_of_int u +. w)
  | _ ->
    ctx.site <- s;
    Arith.add ctx p q

let[@inline] sub_a ctx s p q =
  match p, q with
  | Float u, Float w -> Float (u -. w)
  | Int u, Int w ->
    let r = u - w in
    if (u lxor w) land (u lxor r) < 0 then begin
      ctx.site <- s;
      Arith.sub ctx p q
    end else Int r
  | Float u, Int w -> Float (u -. float_of_int w)
  | Int u, Float w -> Float (float_of_int u -. w)
  | _ ->
    ctx.site <- s;
    Arith.sub ctx p q

let[@inline] mul_a ctx s p q =
  match p, q with
  | Float u, Float w -> Float (u *. w)
  | Float u, Int w -> Float (u *. float_of_int w)
  | Int u, Float w -> Float (float_of_int u *. w)
  | _ ->
    ctx.site <- s;
    Arith.mul ctx p q

let[@inline] div_a ctx s p q =
  match p, q with
  | Float u, Float w -> Float (u /. w)
  | Float u, Int w -> Float (u /. float_of_int w)
  | Int u, Float w -> Float (float_of_int u /. w)
  | Int u, Int w -> Float (float_of_int u /. float_of_int w)
  | _ ->
    ctx.site <- s;
    Arith.div ctx p q

let slow_test ctx s f p q =
  ctx.site <- s;
  match f ctx p q with
  | True -> true
  | False -> false
  | v -> Runtime.fail ctx Type (Messages.condition (Value.describe v))

let[@inline] lt_b ctx s p q =
  match p, q with
  | Int u, Int w -> u < w
  | Float u, Float w -> u < w
  | _ -> slow_test ctx s Arith.lt p q

let[@inline] le_b ctx s p q =
  match p, q with
  | Int u, Int w -> u <= w
  | Float u, Float w -> u <= w
  | _ -> slow_test ctx s Arith.le p q

let[@inline] gt_b ctx s p q =
  match p, q with
  | Int u, Int w -> u > w
  | Float u, Float w -> u > w
  | _ -> slow_test ctx s Arith.gt p q

let[@inline] ge_b ctx s p q =
  match p, q with
  | Int u, Int w -> u >= w
  | Float u, Float w -> u >= w
  | _ -> slow_test ctx s Arith.ge p q

let[@inline] eq_b ctx s p q =
  match p, q with
  | Int u, Int w -> u = w
  | Float u, Float w -> u = w
  | _ -> slow_test ctx s Arith.eq p q

let[@inline] ne_b ctx s p q =
  match p, q with
  | Int u, Int w -> u <> w
  | Float u, Float w -> u <> w
  | _ -> slow_test ctx s Arith.ne p q

(* Entering a frame: its links are in the caller's argument area, so already covered. *)
let[@inline] enter_fast (ctx : ctx) (i : int array) b nb s (ver : version) =
  i.(nb) <- b;
  i.(nb + 1) <- s;
  ctx.b <- nb;
  let need = nb + ver.size in
  if need > ctx.cap then begin
    ctx.site <- s;
    Runtime.grow ctx need
  end;
  tick ctx ver.frame

let[@inline] enter (ctx : ctx) nb s (ver : version) = enter_fast ctx ctx.i ctx.b nb s ver

(* x - d, for a constant d > 0: the result can only overflow upward. *)
let[@inline] sub_const ctx s x d =
  let r = x - d in
  if r > x then begin
    ctx.site <- s;
    Arith.sub_int ctx x d
  end else r

let rec seq_u : (ctx -> unit) list -> ctx -> unit = function
  | [] -> fun _ -> ()
  | [ a ] -> a
  | [ a; b ] -> fun ctx -> a ctx; b ctx
  | [ a; b; d ] -> fun ctx -> a ctx; b ctx; d ctx
  | a :: b :: d :: e :: rest ->
    let r = seq_u rest in
    fun ctx -> a ctx; b ctx; d ctx; e ctx; r ctx

(* Reserves the slot of the indexed array, for [end]. *)
let with_end c uses_end f =
  if not uses_end then f (-1)
  else begin
    let slot = c.off in
    c.off <- slot + 1;
    c.top <- max c.top (c.off + 2);
    let r = f slot in
    c.off <- slot;
    r
  end

type field_cache = { cs : shape; ci : int }

(* The same for a map: its keys last time, and the place of the name in them. *)
type key_cache = { ck : keys; kc : int }

(* Keys that no map holds: a deep map's are [Trie.no_keys]. *)
let no_key = { ck = { ks = [| Undef |]; hs = [| -1 |]; used = 0; deep = Flat }; kc = 0 }

(* What a call finds under a name: field [mi] of the value, or, if [mi] < 0, the method [mg]. *)
(* [mi]: the place of a field, or -1 for a method of the struct, or -2 for a method of an interface, which holds until the
   reload [mr]. *)
type member = { ms : shape; mi : int; mg : t; mr : int }

let no_shape = { sid = -1; names = [||]; sname = None; sm = -1; next = Hashtbl.create 1; checks = [||] }

(* The name of a package, as a use names it: its folder, or its file without .ce. *)
let package_name (w : world) host =
  let folder key m found = if m = host && not (Package.is_source key) then Some key else found in
  match Hashtbl.fold folder w.loaded None with
  | Some dir -> Filename.basename dir
  | None -> Filename.remove_extension (Filename.basename w.modules.(host).path)

let method_of (w : world) (shape : shape) name =
  match shape.sname with
  | Some sn when shape.sm >= 0 -> Hashtbl.find_opt w.methods (shape.sm, sn, name)
  | _ -> None

let takes n = function
  | Fun { proto; _ } -> proto.arity = n
  | Native f -> f.min_args <= n && n <= f.max_args
  | _ -> false

(* What the values of a shape need to meet the interface of package [host]: the methods of their struct, with that number of
   parameters besides the object, or fields that hold functions, which each value must hold. Gives those fields, with their
   numbers of parameters and the place of their method, and the place of the first method that no value of the shape has, or
   -1. A small method is met only in the package of the interface, as in Go. *)
let plan w host (shape : shape) (i : Ast.iface) =
  let rec go k need =
    if k = Array.length i.imethods then need, -1
    else
      let name, ps, _ = i.imethods.(k) in
      let n = Array.length ps and f = Value.field_index shape name in
      if not (Lexer.is_public name || shape.sm = host) then need, k
      else if f >= 0 then go (k + 1) ((f, n, k) :: need)
      else
        match method_of w shape name with
        | Some (Fun { proto; _ }, false) when proto.arity = n + 1 -> go (k + 1) need
        | _ -> need, k
  in
  go 0 []

let holds fields need = List.for_all (fun (f, n, _) -> takes n fields.(f)) need

(* The place of the first method of the interface that a value lacks, or -1. *)
let lacks fields (need, lack) = List.fold_left (fun first (f, n, k) -> if takes n fields.(f) then first else k) lack need

(* The same for a map in a tree, which has no shape to plan by: its keys must hold the functions, so it meets an interface as
   the same map with a shape does. *)
(* The keys of a map are data, so a small method is met by a key only inside the package of the interface, [inside], as by
   the struct of a package. *)
let map_lacks (i : Ast.iface) ~inside m =
  let rec go k =
    if k = Array.length i.imethods then -1
    else
      let name, ps, _ = i.imethods.(k) in
      let key = Text name in
      match Trie.find m (Trie.hash key) key with
      | Undef -> k
      | v when (inside || Lexer.is_public name) && takes (Array.length ps) v -> go (k + 1)
      | _ -> k
  in
  go 0

(* What the maps of these keys need to meet the interface, as [plan] for a shape: every method a public key, whose value
   must be a function of its number of parameters. *)
let key_plan (i : Ast.iface) ~inside (keys : keys) n =
  let rec go k need =
    if k = Array.length i.imethods then need, -1
    else
      let name, ps, _ = i.imethods.(k) in
      let f = Trie.index keys n (Trie.hash (Text name)) (Text name) in
      if f >= 0 && (inside || Lexer.is_public name) then go (k + 1) ((f, Array.length ps, k) :: need) else need, k
  in
  go 0 []
let type_name (t : ptype) = match t.tpkg with Some alias -> alias ^ "." ^ t.tname | None -> t.tname

(* A method as its interface writes it: Scaled(by Number). *)
let method_text (name, ps, _) =
  let param (p : param) =
    match p.ptype with Some t -> p.pname ^ " " ^ type_name t ^ (if t.topt then "?" else "") | None -> p.pname
  in
  name ^ "(" ^ String.concat ", " (Array.to_list (Array.map param ps)) ^ ")"

(* A type written in the code, as a check. A struct is known by its package and its name, and an interface by the methods of
   a value: the last shape that fit is kept, until a reload for an interface. *)
let type_check (w : world) (t : ptype) =
  let shown = type_name t in
  let plain accept = accept, fun x -> Messages.article shown, Value.type_of x in
  let accept, wrong =
    match t.tname, t.tb with
    | "Int", Unresolved -> plain (function Int _ as x -> x | _ -> Undef)
    | "Float", Unresolved -> plain (function Float _ as x -> x | Int i -> Float (float_of_int i) | _ -> Undef)
    | "Number", Unresolved -> plain (function (Int _ | Float _) as x -> x | _ -> Undef)
    | "Bool", Unresolved -> plain (function (True | False) as x -> x | _ -> Undef)
    | "Text", Unresolved -> plain (function Text _ as x -> x | _ -> Undef)
    | "Array", Unresolved -> plain (function Array _ as x -> x | _ -> Undef)
    | "Dict", Unresolved -> plain (function Dict _ as x -> x | _ -> Undef)
    | "Function", Unresolved -> plain (function (Fun _ | Native _) as x -> x | _ -> Undef)
    | name, Cell { m; _ } when Hashtbl.mem w.interfaces (w.modules.(m).host, name) ->
      let host = w.modules.(m).host and last = ref (no_shape, [], -1) and klast = ref (Trie.no_keys, [], -1, -1) in
      (* Written without a package, the type is in the package of the interface. *)
      let inside = t.tpkg = None in
      (* An interface gone at a reload is met by nothing. *)
      let plan_of shape =
        match Hashtbl.find_opt w.interfaces (host, name) with Some i -> plan w host shape i | None -> [], -2
      in
      (function
        | Struct r as x ->
          let s, need, seen = !last in
          if r.shape == s && seen = w.reloads && holds r.fields need then x
          else (
            match plan_of r.shape with
            | need, -1 when holds r.fields need -> last := (r.shape, need, w.reloads); x
            | _ -> Undef)
        | Dict { keys = { deep = Flat; _ } as keys; vals; _ } as x ->
          let k, need, seen, n = !klast in
          if keys == k && n = Array.length vals && seen = w.reloads && holds vals need then x
          else (
            match Hashtbl.find_opt w.interfaces (host, name) with
            | Some i ->
              (match key_plan i ~inside keys (Array.length vals) with
               | need, -1 when holds vals need -> klast := (keys, need, w.reloads, Array.length vals); x
               | _ -> Undef)
            | None -> Undef)
        | Dict _ as x ->
          (match Hashtbl.find_opt w.interfaces (host, name) with Some i when map_lacks i ~inside x < 0 -> x | _ -> Undef)
        | _ -> Undef),
      (function
        | Struct r as x ->
          (match Hashtbl.find_opt w.interfaces (host, name), lacks r.fields (plan_of r.shape) with
           | Some i, k when k >= 0 -> Messages.article shown, Value.type_of x ^ ", which has no " ^ method_text i.imethods.(k)
           | _ -> Messages.article shown, Value.type_of x)
        | Dict _ as x ->
          (match Hashtbl.find_opt w.interfaces (host, name) with
           | Some i when map_lacks i ~inside x >= 0 ->
             Messages.article shown, Value.type_of x ^ ", which has no " ^ method_text i.imethods.(map_lacks i ~inside x)
           | _ -> Messages.article shown, Value.type_of x)
        | x -> Messages.article shown, Value.type_of x)
    | name, Cell { m; _ } ->
      let sm = Value.struct_module name w.modules.(m).host and sname = Some name and last = ref no_shape in
      (function
        | Struct r as x when r.shape == !last -> x
        | Struct r as x when r.shape.sm = sm && r.shape.sname = sname -> last := r.shape; x
        | _ -> Undef),
      (function
        (* Two structs of one name: their packages tell them apart. *)
        | Struct { shape = { sname = Some n; sm = other; _ }; _ } when String.equal n name ->
          Messages.article (package_name w sm ^ "." ^ name), Messages.article (package_name w other ^ "." ^ n)
        | x -> Messages.article shown, Value.type_of x)
    | _ -> assert false (* Resolve binds a type that is not a kind, or refuses it *)
  in
  if t.topt then
    { accept = (function Missing -> Missing | x -> accept x); wrong = (fun x -> let a, b = wrong x in a ^ " or missing", b) }
  else { accept; wrong }

(* The shape of a struct keeps the types of its fields, for the writes: at its definition, and again at a reload. *)
let set_checks w m (f : func) =
  match Resolve.struct_fields f with
  | Some fields ->
    let shape = Value.shape_of w ~sname:f.fname ~m:w.modules.(m).host (Array.map fst fields) in
    shape.checks <-
      (if Array.exists (fun p -> p.ptype <> None) f.params then Array.map (fun p -> Option.map (type_check w) p.ptype) f.params
       else [||])
  | None -> ()

(* A write to a field of a struct with types. Out of line, as a write to an untyped field doesn't need it. *)
let[@inline never] checked ctx (shape : shape) i x =
  match shape.checks.(i) with
  | None -> x
  | Some ch ->
    let y = ch.accept x in
    if y == Undef then begin
      let want, found = ch.wrong x in
      Runtime.fail ctx Type (Messages.wrong_type (Option.value shape.sname ~default:"") shape.names.(i) want found)
    end;
    y

(* A small field of a struct belongs to its package; the keys of a map are data, never private. *)
let reach (ctx : ctx) pm (shape : shape) name =
  if shape.sm >= 0 && shape.sname <> None && (not (Lexer.is_public name)) && ctx.w.modules.(pm).host <> shape.sm then
    Runtime.fail ctx Field (Messages.private_member name)

let field_slot (ctx : ctx) pm (shape : shape) name =
  let i = Value.field_index shape name in
  if i < 0 then
    Runtime.fail ctx (if shape.sname = None then Index else Field)
      (match shape.sname, method_of ctx.w shape name with
       | Some sn, Some _ -> Messages.method_uncalled sn name
       | None, _ -> Messages.dict_absent (Value.describe (Text name))
       | _ -> Messages.no_field name);
  reach ctx pm shape name;
  i

(* The interfaces that give a method to the values of a shape, when their fields hold the functions they need: for each, its
   name, the method and those fields. [hidden]: the struct has a small method of that name, of another package. A reload makes
   it old. *)
type via = { vs : shape; seen : int; can : (string * t * (int * int * int) list) list; hidden : bool }

let no_via = { vs = no_shape; seen = -1; can = []; hidden = false }

let rec via_in shape seen = function
  | [] -> no_via
  | v :: rest -> if v.vs == shape && v.seen = seen then v else via_in shape seen rest

let lost ctx (v : via) name =
  Runtime.fail ctx Field
    (if v.hidden then Messages.private_member name
     else match v.vs.sname with Some sn -> Messages.no_member sn name | None -> Messages.no_field name)

(* What a shape finds under a name that is neither a field nor a method of its struct: the interfaces of the package of the
   call [pm], or of a package that its file uses, that give it a method of that name. Out of line, as only the first call at a
   site for a shape comes here. *)
let[@inline never] by_interface (ctx : ctx) pm (shape : shape) name ~hidden =
  let w = ctx.w and md = ctx.w.modules.(pm) in
  let seen = md.host :: md.uses in
  let can =
    Hashtbl.fold
      (fun (host, iname) i found ->
         match Hashtbl.find_opt w.methods (host, iname, name) with
         | Some (mg, false) when List.mem host seen && (Lexer.is_public name || host = md.host) ->
           (match plan w host shape i with
            | need, -1 -> ((if host = md.host then iname else package_name w host ^ "." ^ iname), mg, need) :: found
            | _ -> found)
         | _ -> found)
      w.interfaces []
  in
  let v = { vs = shape; seen = w.reloads; can = List.sort (fun (a, _, _) (b, _, _) -> String.compare a b) can; hidden } in
  match can with [] -> lost ctx v name | _ -> v

(* A key of a map, else the method of the interface it meets, as by_interface and choose give one to a struct. Looked up at
   each call: a key is cached by the site, and maps seldom call methods of interfaces. *)
let[@inline never] map_member (ctx : ctx) pm x name =
  match Trie.find x (Trie.hash (Text name)) (Text name) with
  | Undef ->
    let w = ctx.w and md = ctx.w.modules.(pm) in
    let seen = md.host :: md.uses in
    let can =
      Hashtbl.fold
        (fun (host, iname) i found ->
           match Hashtbl.find_opt w.methods (host, iname, name) with
           | Some (mg, false) when List.mem host seen && (Lexer.is_public name || host = md.host) && map_lacks i ~inside:(host = md.host) x < 0 ->
             ((if host = md.host then iname else package_name w host ^ "." ^ iname), mg) :: found
           | _ -> found)
        w.interfaces []
    in
    (match List.sort (fun (a, _) (b, _) -> String.compare a b) can with
     | [ (_, mg) ] -> Bound { g = mg; self = x }
     | (a, _) :: (b, _) :: _ -> Runtime.fail ctx Type (Messages.method_two a b name (Value.describe x))
     | [] -> Runtime.fail ctx Index (Messages.dict_absent (Value.describe (Text name))))
  | v -> Value.share v

(* The method that a value gets from the interfaces of [v]: from the one it meets, as two are one too many. *)
let[@inline never] choose ctx (v : via) fields name =
  let rec go found = function
    | [] -> (match found with Some (_, mg) -> mg | None -> lost ctx v name)
    | (iname, mg, need) :: rest when holds fields need ->
      (match found with
       | None -> go (Some (iname, mg)) rest
       | Some (first, _) ->
         let value = match v.vs.sname with Some n -> Messages.article n | None -> "a struct" in
         Runtime.fail ctx Type (Messages.method_two first iname name value))
    | _ :: rest -> go found rest
  in
  go None v.can

(* A field first, then the methods of the struct, then those of the interfaces it meets. A small method is private to the
   package of the struct: the site says which file it is in, [pm], and this runs the first times it meets a shape. *)
let member_of (ctx : ctx) pm (shape : shape) name =
  let i = Value.field_index shape name in
  if i >= 0 then (reach ctx pm shape name; Ok { ms = shape; mi = i; mg = Undef; mr = 0 })
  else
    let sn = Option.value shape.sname ~default:"" in
    match method_of ctx.w shape name with
    | Some (_, true) -> Runtime.fail ctx Field (Messages.static_on_value sn name)
    | Some (mg, false) when Lexer.is_public name || ctx.w.modules.(pm).host = shape.sm -> Ok { ms = shape; mi = -1; mg; mr = 0 }
    | own -> Error (by_interface ctx pm shape name ~hidden:(Option.is_some own))

(* The shapes a site met after its first one: a list of several structs must not search at each call. *)
let max_met = 8

let rec met (shape : shape) = function
  | [] -> None
  | k :: rest -> if k.ms == shape then Some k else met shape rest

(* The field of an array of structs is the array of that field. *)
let rec field_slow ctx pm v name =
  match v with
  | Struct r -> r.fields.(field_slot ctx pm r.shape name)
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } when Trie.index keys (Array.length vals) (Trie.hash (Text name)) (Text name) >= 0 ->
    (* As a field of a struct: an owned map lends it, and a write through it stays in place. *)
    vals.(Trie.index keys (Array.length vals) (Trie.hash (Text name)) (Text name))
  | Dict _ ->
    (match Trie.find v (Trie.hash (Text name)) (Text name) with
     | Undef -> Runtime.fail ctx Index (Messages.dict_absent (Value.describe (Text name)))
     | x -> Value.share x)
  | Array a ->
    Runtime.build ctx (a.rows * a.cols);
    Arrays.of_vals a.rows a.cols
      (Array.init (a.rows * a.cols) (fun k -> Value.share (field_slow ctx pm (Value.elt a k) name)))
  | _ -> Runtime.fail ctx Type (Messages.field_of (Value.describe v) name)

(* [Rkey]: an index by a text written in the code, m["City"], which keeps a map flat as m.City does. *)
type resolved_step = Rfield of string | Rindex of Arrays.ix array | Rkey of string

let step_read ctx pm v st =
  match st with
  | Rfield name -> field_slow ctx pm v name
  | Rindex ixs -> Arrays.read ctx v ixs
  | Rkey k -> Arrays.read1 ctx v (Arrays.Key (Text k))

(* A key written in an owned map, in place, or the map that takes its place; else a new map. Either is returned. *)
let write_key ctx v k x =
  match v with
  | Dict { keys = { deep = Flat; _ } as keys; vals; d_owned = true } ->
    Dict.check ctx k;
    let h = Trie.hash k in
    let i = Trie.index keys (Array.length vals) h k in
    if i >= 0 then (vals.(i) <- x; v) else Trie.add_absent v h k (Value.share x)
  | Dict { keys = { deep = Deep _; _ }; d_owned = true; _ } ->
    Dict.check ctx k;
    Trie.put_owned v (Trie.hash k) k (Value.share x)
  | _ -> Dict.put ctx "" k (Value.share x) v

(* Writes to an owned container. A new key gives a new map, which is returned. *)
let step_write ctx pm v st x =
  match st, v with
  | Rindex ixs, Dict _ -> write_key ctx v (Arrays.key_of ctx ixs) x
  | (Rfield k | Rkey k), Dict _ -> write_key ctx v (Text k) x
  | Rindex ixs, _ ->
    Arrays.write ctx v ixs x;
    v
  | Rkey k, _ ->
    Arrays.write ctx v [| Arrays.Key (Text k) |] x;
    v
  | Rfield name, Struct r ->
    let i = Value.field_index r.shape name in
    if i < 0 then Runtime.fail ctx Field (Messages.named_field (Option.value r.shape.sname ~default:"") name);
    reach ctx pm r.shape name;
    r.fields.(i) <- (if Array.length r.shape.checks = 0 then x else checked ctx r.shape i x);
    v
  | Rfield name, _ -> Runtime.fail ctx Type (Messages.field_of (Value.describe v) name)

(* The slow path of a write to a variable: owns its value, writes, and stores it again if the write gave a new one. *)
let write_root ctx pm set x st y =
  let top = Runtime.own ctx x in
  let after = step_write ctx pm top st y in
  if after != x then set ctx after

let new_proto ~file ~m (f : func) =
  { pname = f.fname; file; pm = m; func = f; versions = []; generic = None; by_tag = [];
    arity = Array.length f.params; last = No_call }

(* No jump table: an indirect branch predicts badly when types alternate. *)
let[@inline] is_float v = match v with Float _ -> true | _ -> false
let[@inline] is_int v = match v with Int _ -> true | _ -> false

let arg_other v =
  match v with
  | Array { store = F _; _ } -> 2
  | _ -> 3

let[@inline] arg_type v = if is_float v then 1 else if is_int v then 0 else arg_other v

let[@inline] put (ctx : ctx) pk nb k x =
  let e = pk.(k) in
  let p = nb + (e lsr 2) in
  match e land 3 with
  | 1 -> ctx.i.(p) <- to_i ctx x
  | 2 -> Float.Array.set ctx.f p (to_f ctx x)
  | _ -> ctx.v.(p) <- x

(* The tag of the generic version. Positive and out of reach of a real tag, which fits in 40 bits: the cache key thus
   keeps the argument count, placed above. *)
let no_tag = (1 lsl 42) - 1

(* Two bits per argument: the real type of each. no_spec has a single tag. *)
let arg_tag (ctx : ctx) nb n =
  if ctx.w.no_spec then no_tag
  else begin
    let tag = ref 0 and omitted = ref false in
    for i = 0 to n - 1 do
      let x = ctx.v.(nb + i) in
      if x == Undef then omitted := true;
      tag := !tag lor (arg_type x lsl (2 * i))
    done;
    (* An argument skipped by a named call: only the generic version computes its default. *)
    if !omitted then no_tag else !tag
  end

(* An argument: a local variable, or a closure. *)
let[@inline] arg_value (ctx : ctx) slot (f : ctx -> t) = if slot >= 0 then ctx.v.(ctx.b + slot) else f ctx

(* How a call passes an argument. [Give]: the caller's variable ends with the call, so the function owns the value.
   [Lend]: the parameter only reads it, and it stays owned for the caller, who is stopped meanwhile. [Share]: a second
   reference. A dynamic call lends what is marked [Lend], unless the function it reaches keeps that parameter. *)
type pass = Give | Lend | Share

let[@inline] share_if bits k x = if bits land (1 lsl k) <> 0 then ignore (Value.share x)

(* What a function keeps of the arguments of a call. The object of a method comes before them, and the mask only reaches
   parameter 61: the argument that lands on the next one counts as kept. *)
let args_kept g =
  match g with
  | Fun { proto; _ } -> proto.func.kept
  | Bound { g = Fun { proto; _ }; _ } -> (proto.func.kept lsr 1) lor (1 lsl 61)
  | _ -> -1

let share_kept (ctx : ctx) g nb n lent =
  let bits = args_kept g land lent in
  if bits <> 0 then
    for k = 0 to min n 62 - 1 do
      share_if bits k ctx.v.(nb + k)
    done

(* Reads a bounded part of the expression, or calls nested in calls would cost a square. Past it the answer is yes, which
   only shares an argument. *)
let any_node p (e : expr) =
  let left = ref 256 in
  let rec go (e : expr) =
    decr left;
    !left < 0 || p e
    || begin
      let found = ref false in
      Resolve.children (fun x -> if go x then found := true) e;
      !found
    end
  in
  go e

let bare (e : expr) = match e.e with Var { b = Local i; _ } -> i | _ -> -1
let writes = any_node (fun e -> match e.e with Set _ | Assign _ -> true | _ -> false)
let mentions i = any_node (fun e -> bare e = i)

(* A module variable is within reach of another fiber, which may run while the function sleeps. *)
let reads_module = any_node (fun e -> match e.e with Var { b = Cell { stable = false; _ }; _ } -> true | _ -> false)

let[@inline] finish (ctx : ctx) (proto : proto) (ver : version) env nb b s =
  enter_fast ctx ctx.i b nb s ver;
  let caps = proto.func.captures in
  if Array.length caps > 0 then begin
    let map = ver.map in
    for j = 0 to Array.length caps - 1 do
      ctx.v.(nb + map.(snd caps.(j))) <- env.(j)
    done
  end;
  let r = if ver.ret == TF then Float (ver.rf ctx) else ver.rv ctx in
  ctx.b <- b;
  r

let rec find_in key = function
  | [] -> None
  | (k, v) :: rest -> if k = key then Some v else find_in key rest

let tag_type tag i =
  match (tag lsr (2 * i)) land 3 with
  | 0 -> TI
  | 1 -> TF
  | 2 -> TFA
  | _ -> TA

let[@inline never] fa_slow1 ctx x k s =
  ctx.site <- s;
  to_f ctx (Arrays.read1 ctx x (Arrays.At k))

let[@inline] fa_get (ctx : ctx) slot k s =
  match ctx.v.(ctx.b + slot) with
  | Array { store = F d; rows; cols; _ } when k >= 1 && k <= rows * cols -> Float.Array.get d (k - 1)
  | x -> fa_slow1 ctx x k s

let wrap : 'a. func -> int -> (ctx -> unit) option -> (ctx -> t -> 'a) -> (ctx -> 'a) -> ctx -> 'a =
  fun f frame prologue unbox body ->
  let once = match prologue with None -> body | Some p -> fun ctx -> p ctx; body ctx in
  let guarded =
    if f.has_return then (fun ctx -> try once ctx with Return_value v -> unbox ctx v) else once
  in
  let looped =
    if f.has_self_tail then begin
      let rec loop (ctx : ctx) =
        let r = guarded ctx in
        if ctx.again then begin
          ctx.again <- false;
          tick ctx frame;
          loop ctx
        end else r
      in
      loop
    end else guarded
  in
  looped

(* A version that keeps a value as an Int or a Float already knows whether it fits a number type. *)
let known_number (t : ptype) ty =
  (ty == TI || ty == TF) && t.tb = Unresolved && (t.tname = "Number" || t.tname = (if ty == TI then "Int" else "Float"))

(* The return type at a way out of the function, as for a parameter: the version may already know the answer. Else the value
   is checked there, and a wrong one stops the program. *)
let result_check c pos known : (ctx -> t -> t) option =
  match c.func.ret with
  | Some t when not (known_number t known) ->
    let ch = type_check c.w t and s = site c pos in
    let wrong (ctx : ctx) x =
      ctx.site <- s;
      let want, found = ch.wrong x in
      Runtime.fail ctx Type (Messages.wrong_result c.func.fname want found)
    in
    Some (fun ctx x -> let y = ch.accept x in if y == Undef then wrong ctx x else y)
  | _ -> None

(* The check of the last value of the body, at its last expression. A call to itself in tail position is no way out: it
   jumps back. *)
let tail_check c =
  let f = c.func in
  let last =
    match f.body with
    | [||] -> f.fpos
    | b -> (match b.(Array.length b - 1) with { e = Return { rvalue = Some v; _ }; _ } -> v.pos | e -> e.pos)
  in
  match result_check c last c.ver.ret with
  | Some check when f.has_self_tail -> Some (fun ctx x -> if ctx.again then x else check ctx x)
  | found -> found

let rec compile_version (ctx : ctx) (ver : version) =
  let w = ctx.w in
  Infer.run w ver;
  let f = ver.owner.func in
  let c =
    { w; file = ver.owner.file; fn = ver.owner.pname; func = f; ver; tv = ver.tv; tn = ver.tn; map = ver.map;
      off = ver.frame; top = ver.frame + 2; ends = []; live = Bytes.empty }
  in
  let generic = match ver.owner.generic with Some g -> g == ver | None -> false in
  let defaults =
    List.filter_map
      (fun k ->
         match f.params.(k).default with
         | Some d when generic ->
           let d = ce c d and slot = ver.map.(k) in
           Some (fun (ctx : ctx) ->
               match ctx.v.(ctx.b + slot) with
               | Undef ->
                 let x = d ctx in
                 ctx.v.(ctx.b + slot) <- x
               | _ -> ())
         | Some d when ver.sg.(k) == TBot -> Some (store_var c k d)
         | _ -> None)
      (List.init (Array.length f.params) Fun.id)
  in
  let np = Array.length f.params in
  let captured = Array.map snd f.captures in
  let unset =
    List.filter
      (fun i -> f.maybe_undef.(i) && i >= np && (not (Array.mem i captured)) && cell_of c i < 0)
      (List.init f.nvars Fun.id)
  in
  let checks = List.filter_map (fun k -> Option.bind f.params.(k).ptype (param_check c k)) (List.init np Fun.id) in
  let writes =
    List.map (fun i -> let k = ver.map.(i) in fun (ctx : ctx) -> ctx.v.(ctx.b + k) <- Undef) unset @ defaults @ checks
  in
  let prologue = if writes = [] then None else Some (seq_u writes) in
  (match ver.ret with
   | TI ->
     let body = ci_block c f.body in
     let body = match tail_check c with Some check -> fun ctx -> to_i ctx (check ctx (Int (body ctx))) | None -> body in
     let entry = wrap f ver.frame prologue to_i body in
     ver.ri <- entry;
     ver.rv <- (fun ctx -> Int (entry ctx));
     ver.rf <- (fun ctx -> float_of_int (entry ctx))
   | TF ->
     let body = cf_block c f.body in
     let body = match tail_check c with Some check -> fun ctx -> to_f ctx (check ctx (Float (body ctx))) | None -> body in
     let entry = wrap f ver.frame prologue to_f body in
     ver.rf <- entry;
     ver.rv <- (fun ctx -> Float (entry ctx));
     ver.ri <- (fun ctx -> to_i ctx (Float (entry ctx)))
   | _ ->
     let body = ctail_block c f.body in
     let body = match tail_check c with Some check -> fun ctx -> check ctx (body ctx) | None -> body in
     let entry = wrap f ver.frame prologue (fun _ v -> v) body in
     ver.rv <- entry;
     ver.ri <- (fun ctx -> to_i ctx (entry ctx));
     ver.rf <- (fun ctx -> to_f ctx (entry ctx)));
  ver.size <- c.top;
  if ctx.b + ver.size > ctx.cap then Runtime.grow ctx (ctx.b + ver.size)

(* A typed parameter, after its default. Its version may already know the answer: an Int or a Float for a number. Else
   the value is checked, and a wrong one stops the program at the call. *)
and param_check c k (t : ptype) : (ctx -> unit) option =
  if known_number t c.tv.(k) then None
  else begin
    let ch = type_check c.w t and slot = c.map.(k) in
    let wrong (ctx : ctx) x =
      let b = ctx.b in
      ctx.site <- ctx.i.(b + 1);
      ctx.b <- Runtime.link_base ctx.i.(b);
      let want, found = ch.wrong x in
      Runtime.fail ctx Type (Messages.wrong_type c.func.fname c.func.params.(k).pname want found)
    in
    match c.tv.(k) with
    | TI -> Some (fun ctx -> wrong ctx (Int (iget ctx slot)))
    | TF -> Some (fun ctx -> wrong ctx (Float (fget ctx slot)))
    | _ ->
      Some (fun ctx ->
          let p = ctx.b + slot in
          let x = ctx.v.(p) in
          let y = ch.accept x in
          if y != x then if y == Undef then wrong ctx x else ctx.v.(p) <- y)
  end

(* Writes the value of an expression to a variable, according to its type. *)
and store_var c i (e : expr) : ctx -> unit =
  let k = c.map.(i) in
  match c.tv.(i) with
  | TI when cell_of c i < 0 ->
    (match e.e with
     | Bin (Add, { e = Var { b = Local j; _ }; _ }, { e = Lint d; _ }) when j = i ->
       let s = site c e.pos in
       fun ctx ->
         let p = ctx.b + k in
         ctx.i.(p) <- add_i ctx s ctx.i.(p) d
     | _ ->
       let a = ci c e in
       fun ctx ->
         let x = a ctx in
         ctx.i.(ctx.b + k) <- x)
  | TF when cell_of c i < 0 ->
    (match e.e with
     | Bin (op, a, b) when ty c e == TF && (op = Add || op = Sub || op = Mul || op = Div) && not (super_float_applies c a b) ->
       store_float c k op (fleaf3 c a) (fleaf3 c b)
     | _ ->
       let a = cf c e in
       fun ctx ->
         let x = a ctx in
         Float.Array.set ctx.f (ctx.b + k) x)
  | _ ->
    let cell = cell_of c i in
    if cell >= 0 then begin
      let a = ce c e in
      let md = c.w.modules.(c.ver.owner.pm) in
      fun ctx -> md.cells.(cell) <- a ctx
    end else begin
      match e.e with
      | Index ({ e = Var { b = Local r; _ }; _ }, [| Ix ix |], false) when plain_local c r && ty c ix == TI ->
        let slot = c.map.(r) and idx = ci c ix and s = site c e.pos in
        fun ctx ->
          let p = idx ctx in
          let x =
            match ctx.v.(ctx.b + slot) with
            | Array { store = V d; rows; cols; _ } when p >= 1 && p <= rows * cols -> d.(p - 1)
            | Array { store = I d; rows; cols; _ } when p >= 1 && p <= rows * cols -> Int d.(p - 1)
            | base ->
              ctx.site <- s;
              Arrays.read1 ctx base (Arrays.At p)
          in
          (match x with
           | Array r -> r.a_owned <- false
           | Struct r -> r.r_owned <- false
           | Dict r -> r.d_owned <- false
           | _ -> ());
          ctx.v.(ctx.b + k) <- x
      | Var _ | Index _ | Field _ ->
        let a = cv c e in
        fun ctx ->
          let x = a ctx in
          (match x with
           | Array r -> r.a_owned <- false
           | Struct r -> r.r_owned <- false
           | Dict r -> r.d_owned <- false
           | _ -> ());
          ctx.v.(ctx.b + k) <- x
      | Call
          { callee = { e = Var { b = Cell { m; k = ck; stable = true }; _ }; _ };
            args = [| { aname = None; value = key }; { aname = None; value }; { aname = None; value = { e = Var { b = Local j; _ }; _ } } |];
            _ }
        when j = i && plain_local c i && (not c.w.hooks) && (not (mentions i key)) && (not (mentions i value))
             && (match c.w.modules.(m).cells.(ck) with Native { nname = "Put"; _ } -> true | _ -> false) ->
        (* m = Put(k, x, m) is m[k] = x: the map is owned, and written in place unless something else holds it. *)
        let put = c.w.modules.(m).cells.(ck) and s = site c e.pos and pm = c.ver.owner.pm in
        let kf = ce c key and vf = ce c value in
        fun ctx ->
          let kx = kf ctx in
          let y = vf ctx in
          let x = ctx.v.(ctx.b + k) in
          ctx.site <- s;
          ctx.v.(ctx.b + k) <-
            (match x, put with
             | Dict _, _ -> step_write ctx pm (Runtime.own ctx x) (Rindex [| Arrays.Key kx |]) y
             | _, Native n -> n.run ctx [| kx; y; x |]
             | _ -> assert false)
      | Call call when plain_local c i && not c.w.hooks ->
        (* a = f(a): the variable ends with the call. A debugger still shows it to the callee's stops. *)
        let a = call_any ~target:i c e call in
        fun ctx ->
          let x = a ctx in
          ctx.v.(ctx.b + k) <- x
      | _ ->
        let a = ce c e in
        fun ctx ->
          let x = a ctx in
          ctx.v.(ctx.b + k) <- x
    end

(* x = a op b on floats: the computation and the write in the same closure. *)
and store_float c k op x y : ctx -> unit =
  ignore c;
  let[@inline] set (ctx : ctx) v = Float.Array.set ctx.f (ctx.b + k) v in
  match op, x, y with
  | Add, `L i, `L j -> fun ctx -> set ctx (fget ctx i +. fget ctx j)
  | Add, `L i, `K q -> fun ctx -> set ctx (fget ctx i +. q)
  | Add, `K q, `L j -> fun ctx -> set ctx (q +. fget ctx j)
  | Add, `L i, `X g -> fun ctx -> let v = g ctx in set ctx (fget ctx i +. v)
  | Add, `X f, `L j -> fun ctx -> let u = f ctx in set ctx (u +. fget ctx j)
  | Add, `X f, `K q -> fun ctx -> set ctx (f ctx +. q)
  | Add, `K q, `X g -> fun ctx -> set ctx (q +. g ctx)
  | Add, `X f, `X g ->
    fun ctx ->
      let u = f ctx in
      let v = g ctx in
      set ctx (u +. v)
  | Sub, `L i, `L j -> fun ctx -> set ctx (fget ctx i -. fget ctx j)
  | Sub, `L i, `K q -> fun ctx -> set ctx (fget ctx i -. q)
  | Sub, `K q, `L j -> fun ctx -> set ctx (q -. fget ctx j)
  | Sub, `L i, `X g -> fun ctx -> let v = g ctx in set ctx (fget ctx i -. v)
  | Sub, `X f, `L j -> fun ctx -> let u = f ctx in set ctx (u -. fget ctx j)
  | Sub, `X f, `K q -> fun ctx -> set ctx (f ctx -. q)
  | Sub, `K q, `X g -> fun ctx -> set ctx (q -. g ctx)
  | Sub, `X f, `X g ->
    fun ctx ->
      let u = f ctx in
      let v = g ctx in
      set ctx (u -. v)
  | Mul, `L i, `L j -> fun ctx -> set ctx (fget ctx i *. fget ctx j)
  | Mul, `L i, `K q -> fun ctx -> set ctx (fget ctx i *. q)
  | Mul, `K q, `L j -> fun ctx -> set ctx (q *. fget ctx j)
  | Mul, `L i, `X g -> fun ctx -> let v = g ctx in set ctx (fget ctx i *. v)
  | Mul, `X f, `L j -> fun ctx -> let u = f ctx in set ctx (u *. fget ctx j)
  | Mul, `X f, `K q -> fun ctx -> set ctx (f ctx *. q)
  | Mul, `K q, `X g -> fun ctx -> set ctx (q *. g ctx)
  | Mul, `X f, `X g ->
    fun ctx ->
      let u = f ctx in
      let v = g ctx in
      set ctx (u *. v)
  | Div, `L i, `L j -> fun ctx -> set ctx (fget ctx i /. fget ctx j)
  | Div, `L i, `K q -> fun ctx -> set ctx (fget ctx i /. q)
  | Div, `K q, `L j -> fun ctx -> set ctx (q /. fget ctx j)
  | Div, `L i, `X g -> fun ctx -> let v = g ctx in set ctx (fget ctx i /. v)
  | Div, `X f, `L j -> fun ctx -> let u = f ctx in set ctx (u /. fget ctx j)
  | Div, `X f, `K q -> fun ctx -> set ctx (f ctx /. q)
  | Div, `K q, `X g -> fun ctx -> set ctx (q /. g ctx)
  | Div, `X f, `X g ->
    fun ctx ->
      let u = f ctx in
      let v = g ctx in
      set ctx (u /. v)
  | Add, `K p, `K q -> let r = p +. q in fun ctx -> set ctx r
  | Sub, `K p, `K q -> let r = p -. q in fun ctx -> set ctx r
  | Mul, `K p, `K q -> let r = p *. q in fun ctx -> set ctx r
  | Div, `K p, `K q -> let r = p /. q in fun ctx -> set ctx r
  | _ -> assert false

(* An expression, as a boxed value. *)
and cv c (e : expr) : ctx -> t =
  match e.e with
  | Lint i -> let v = Int i in fun _ -> v
  | Lfloat x -> let v = Float x in fun _ -> v
  | Var n -> var c e n
  | _ ->
    match ty c e with
    | TI ->
      let i = ci c e in
      fun ctx -> Int (i ctx)
    | TF ->
      let f = cf c e in
      fun ctx -> Float (f ctx)
    | _ -> ca c e

(* The generic form. *)
and ca c (e : expr) : ctx -> t =
  match e.e with
  | Lint i -> let v = Int i in fun _ -> v
  | Lfloat x -> let v = Float x in fun _ -> v
  | Lbool b -> let v = Value.of_bool b in fun _ -> v
  | Lmissing -> fun _ -> Missing
  | Ltext s -> let v = Text s in fun _ -> v
  | Interp parts -> interp c parts e.pos
  | Var n -> var c e n
  | Neg a ->
    let a = cv c a and s = site c e.pos in
    fun ctx ->
      let x = a ctx in
      ctx.site <- s;
      Arith.neg ctx x
  | Bin (op, a, b) -> binary c e op a b
  | Not _ | And _ | Or _ -> let b = cb c e in fun ctx -> Value.of_bool (b ctx)
  | Call call -> call_any c e call
  | If (cond, yes, no) ->
    let cond = cb c cond and yes = cblock c yes and no = cblock c no in
    fun ctx -> if cond ctx then yes ctx else no ctx
  | Lambda f -> closure c f
  | Range (a, b) ->
    let l = bound c a e.pos and h = bound c b e.pos and s = site c e.pos in
    fun ctx ->
      let lo = l ctx in
      let hi = h ctx in
      ctx.site <- s;
      Arrays.int_range ctx lo hi
  | In_op (a, b) -> member c e a b
  | Array_lit rows -> array_lit c e rows
  | Comp { cbody; cvar; csrc; cguard } -> comprehension c cbody cvar csrc cguard
  | Index (b, ixs, uses_end) -> index_read c e b ixs uses_end
  | Field (b, name) -> (match struct_from c b name with Some v -> fun _ -> v | None -> field_read c e b name)
  | Match { subject; arms } -> match_expr c e subject arms (ce c)
  | Struct_lit { sname; sfields } -> struct_lit c sname sfields
  | End_index -> end_index c
  | Question a -> question c e a
  | Return { rvalue; tail } ->
    let v = match rvalue with Some v -> if tail then ctail c v else ce c v | None -> fun _ -> Missing in
    if tail then v
    else (
      match result_check c e.pos (match rvalue with Some v -> ty c v | None -> TA) with
      | None -> fun ctx -> raise_notrace (Return_value (v ctx))
      | Some check -> fun ctx -> raise_notrace (Return_value (check ctx (v ctx))))
  | Assign _ | While _ | For _ | Set _ | Break | Fn_def _ | Destructure _ | Use _ | Interface _ | Hook _ ->
    let u = cu c e in
    fun ctx -> u ctx; Missing

(* A value about to be stored elsewhere: a second reference leads to it, unless it is new. *)
and ce c (e : expr) : ctx -> t =
  match e.e with
  | Var { b = Local i; _ } when plain_local c i ->
    let k = c.map.(i) in
    fun ctx ->
      let x = ctx.v.(ctx.b + k) in
      (match x with
       | Array r -> r.a_owned <- false
       | Struct r -> r.r_owned <- false
       | Dict r -> r.d_owned <- false
       | _ -> ());
      x
  | Var _ | Index _ | Field _ ->
    let v = cv c e in
    fun ctx -> Value.share (v ctx)
  | If (cond, yes, no) ->
    let cond = cb c cond and yes = ce_block c yes and no = ce_block c no in
    fun ctx -> if cond ctx then yes ctx else no ctx
  | _ -> cv c e

and ce_block c (b : block) : ctx -> t =
  let n = Array.length b in
  if n = 0 then fun _ -> Missing
  else if n = 1 then ce c b.(0)
  else begin
    let pre = seq_u (List.map (cu c) (Array.to_list (Array.sub b 0 (n - 1)))) in
    let last = ce c b.(n - 1) in
    fun ctx -> pre ctx; last ctx
  end

(* In tail position, a local variable dies with the frame: it stays owned. *)
and ctail c (e : expr) : ctx -> t =
  match e.e with
  | Var { b = Local _; _ } -> cv c e
  | Call ({ self_tail = true; _ } as call) -> call_any c e call
  | If (cond, yes, no) ->
    let cond = cb c cond and yes = ctail_block c yes and no = ctail_block c no in
    fun ctx -> if cond ctx then yes ctx else no ctx
  | Match { subject; arms } -> match_expr c e subject arms (ctail c)
  | Return { tail = true; rvalue = Some v } -> ctail c v
  | _ -> ce c e

and ctail_block c (b : block) : ctx -> t =
  let n = Array.length b in
  if n = 0 then fun _ -> Missing
  else if n = 1 then ctail c b.(0)
  else begin
    let pre = seq_u (List.map (cu c) (Array.to_list (Array.sub b 0 (n - 1)))) in
    let last = ctail c b.(n - 1) in
    fun ctx -> pre ctx; last ctx
  end

(* A bound of a:b, evaluated once. A float with an integer value is accepted. *)
and bound c (e : expr) pos : ctx -> int =
  if ty c e == TI then ci c e
  else begin
    let v = cv c e and s = site c pos in
    fun ctx ->
      match v ctx with
      | Int i -> i
      | x ->
        ctx.site <- s;
        Arrays.range_bound ctx x
  end

and member c e a b =
  let x = cv c a and s = site c e.pos in
  match b.e with
  | Range (l, h) ->
    let l = bound c l b.pos and h = bound c h b.pos in
    fun ctx ->
      let v = x ctx in
      let lo = l ctx in
      let hi = h ctx in
      (match v with
       | Int i -> Value.of_bool (i >= lo && i <= hi)
       | Float f -> Value.of_bool (Float.is_integer f && f >= float_of_int lo && f <= float_of_int hi)
       | _ -> False)
  | _ ->
    let y = cv c b in
    fun ctx ->
      let v = x ctx in
      let xs = y ctx in
      ctx.site <- s;
      Arrays.mem ctx v xs

and array_lit c e rows =
  let r = Array.length rows in
  let cols = if r = 0 then 0 else Array.length rows.(0) in
  if Array.exists (fun row -> Array.length row <> cols) rows then
    raise_at (site c e.pos) Type Messages.rows_differ
  else begin
    let cells = Array.map (Array.map (ce c)) rows in
    fun ctx ->
      let out = Array.make (r * cols) Missing in
      for i = 0 to r - 1 do
        let row = cells.(i) in
        for j = 0 to cols - 1 do
          let x = row.(j) ctx in
          out.((j * r) + i) <- x
        done
      done;
      Arrays.of_vals r cols out
  end

(* A loop over a:b or over an array. [st] is the state of one run of the loop. *)
and loop_over : 'st. c -> expr -> (ctx -> t -> unit) -> ('st -> ctx -> unit) -> 'st -> ctx -> unit =
  fun c iter set body ->
  let off = c.off in
  match iter.e with
  | Range (a, b) ->
    let l = bound c a iter.pos and h = bound c b iter.pos in
    fun st ctx ->
      let lo = l ctx in
      let hi = h ctx in
      for i = lo to hi do
        set ctx (Int i);
        body st ctx;
        tick ctx off
      done
  | _ ->
    let src = cv c iter and s = site c iter.pos in
    fun st ctx ->
      match src ctx with
      | Array a ->
        (* The traversal keeps a reference: a write in the body must copy. *)
        a.a_owned <- false;
        let n = a.rows * a.cols in
        for k = 0 to n - 1 do
          set ctx (Value.share (Value.elt a k));
          body st ctx;
          tick ctx off
        done
      | v ->
        ctx.site <- s;
        Runtime.fail ctx Type (Messages.cant_loop (Value.describe v))

and comprehension c cbody cvar csrc cguard =
  let set = setter c cvar in
  let push : Arrays.builder -> ctx -> unit =
    if ty c cbody == TF then
      let v = cf c cbody in
      fun out ctx -> Arrays.add_float ctx out (v ctx)
    else if ty c cbody == TI then
      let v = ci c cbody in
      fun out ctx -> Arrays.add_int ctx out (v ctx)
    else
      let v = ce c cbody in
      fun out ctx -> Arrays.add ctx out (v ctx)
  in
  let body =
    match Option.map (cb c) cguard with
    | None -> push
    | Some g -> fun out ctx -> if g ctx then push out ctx
  in
  let run = loop_over c csrc set body in
  fun ctx ->
    let out = Arrays.builder () in
    run out ctx;
    Arrays.built out

(* An index at run time. *)
and index_arg c (ix : index) pos : ctx -> Arrays.ix =
  match ix with
  | All -> fun _ -> Arrays.Every
  | Ix { e = Range (a, b); pos = p; _ } ->
    let l = bound c a p and h = bound c b p in
    fun ctx ->
      let lo = l ctx in
      let hi = h ctx in
      Arrays.Slice (lo, hi)
  | Ix e ->
    let v = cv c e and s = site c pos in
    fun ctx ->
      let x = v ctx in
      ctx.site <- s;
      Arrays.ix_of ctx x

and index_read c e b ixs uses_end =
  let base = cv c b and s = site c e.pos in
  let n = Array.length ixs in
  with_end c uses_end (fun slot ->
      let saved = c.ends in
      let args =
        Array.mapi
          (fun d ix ->
             c.ends <- (slot, d, n) :: saved;
             index_arg c ix e.pos)
          ixs
      in
      c.ends <- saved;
      let keep : ctx -> t -> unit =
        if slot < 0 then fun _ _ -> () else fun ctx x -> ctx.v.(ctx.b + slot) <- x
      in
      match ixs, args with
      | [| Ix { e = Ltext k; _ } |], _ when not uses_end ->
        (* m["Name"] costs what m.Name costs. *)
        let cache = ref no_key and key = Text k in
        let h = Trie.hash key in
        fun ctx ->
          let x = base ctx in
          let last = !cache in
          (match x with
           | Dict { keys; vals; _ } when keys == last.ck -> vals.(last.kc)
           | Dict { keys = { deep = Flat; _ } as keys; vals; _ } when Trie.index keys (Array.length vals) h key >= 0 ->
             let i = Trie.index keys (Array.length vals) h key in
             if Trie.is_whole keys then cache := { ck = keys; kc = i };
             vals.(i)
           | _ ->
             ctx.site <- s;
             Arrays.read1 ctx x (Arrays.Key key))
      | [| Ix i |], _ when (not uses_end) && ty c i == TI ->
        let idx = ci c i in
        let read (ctx : ctx) x k =
          match x with
          | Array { store = V d; rows; cols; _ } when k >= 1 && k <= rows * cols -> d.(k - 1)
          | Array { store = I d; rows; cols; _ } when k >= 1 && k <= rows * cols -> Int d.(k - 1)
          | Array { store = F d; rows; cols; _ } when k >= 1 && k <= rows * cols -> Float (Float.Array.get d (k - 1))
          | _ ->
            ctx.site <- s;
            Arrays.read1 ctx x (Arrays.At k)
        in
        (match leaf c b with
         | `L slot ->
           fun ctx ->
             let k = idx ctx in
             read ctx ctx.v.(ctx.b + slot) k
         | _ ->
           fun ctx ->
             let x = base ctx in
             read ctx x (idx ctx))
      | [| Ix { e = (Var _ | Lint _ | Bin _ | Call _ | Neg _ | Field _ | Index _ ); _ } as ix |], _ when not uses_end ->
        let v = (match ix with Ix i -> cv c i | All -> assert false) in
        fun ctx ->
          let x = base ctx in
          let i = v ctx in
          (match x, i with
           | Array a, Int k when k >= 1 && k <= a.rows * a.cols ->
             (match a.store with
              | F d -> Float (Float.Array.get d (k - 1))
              | I d -> Int d.(k - 1)
              | V d -> d.(k - 1))
           | Dict _, (Text _ | Int _) ->
             (match Trie.find x (Trie.hash i) i with
              | Undef ->
                ctx.site <- s;
                Arrays.read1 ctx x (Arrays.ix_of ctx i)
              | y -> Value.share y)
           | _ ->
             ctx.site <- s;
             Arrays.read1 ctx x (Arrays.ix_of ctx i))
      | _, [| a |] ->
        fun ctx ->
          let x = base ctx in
          keep ctx x;
          let i = a ctx in
          ctx.site <- s;
          Arrays.read1 ctx x i
      | _, [| a; d |] ->
        fun ctx ->
          let x = base ctx in
          keep ctx x;
          let i = a ctx in
          let j = d ctx in
          ctx.site <- s;
          Arrays.read2 ctx x i j
      | _ -> raise_at s Index Messages.index_count)

(* e?: the value of an Ok, or an early return of the Err. *)
and question c e a =
  let v = ce c a and s = site c e.pos in
  let ok = Value.shape_of c.w ~sname:"Ok" [| "Value" |] in
  let err = Value.shape_of c.w ~sname:"Err" [| "Error" |] in
  fun ctx ->
    match v ctx with
    | Struct r when r.shape == ok -> Value.share r.fields.(0)
    | Struct r as x when r.shape == err -> raise_notrace (Return_value x)
    | x ->
      ctx.site <- s;
      Runtime.fail ctx Type (Messages.question_value (Value.describe x))

and struct_lit c sname fields =
  let names = Array.map fst fields in
  let n = Array.length names in
  if sname = None && (n > Trie.width || List.length (List.sort_uniq String.compare (Array.to_list names)) < n) then begin
    let vals = Array.map (fun (_, v) -> ce c v) fields in
    fun ctx -> Dict.of_items ctx (Array.init (2 * n) (fun j ->
        if j land 1 = 0 then Text names.(j / 2) else Value.share (vals.(j / 2) ctx)))
  end else if sname = None then begin
    (* The maps of one literal share their keys. *)
    let keys = Trie.names names in
    match Array.map (fun (_, v) -> ce c v) fields with
    | [| a; b |] ->
      fun ctx ->
        let x = a ctx in
        let y = b ctx in
        Dict { keys; vals = [| x; y |]; d_owned = true }
    | [| a; b; d |] ->
      fun ctx ->
        let x = a ctx in
        let y = b ctx in
        let z = d ctx in
        Dict { keys; vals = [| x; y; z |]; d_owned = true }
    | [| a; b; d; e |] ->
      fun ctx ->
        let x = a ctx in
        let y = b ctx in
        let z = d ctx in
        let w = e ctx in
        Dict { keys; vals = [| x; y; z; w |]; d_owned = true }
    | vals -> fun ctx -> Dict { keys; vals = Array.map (fun v -> v ctx) vals; d_owned = true }
  end else
  let shape = Value.shape_of c.w ?sname ~m:c.w.modules.(c.ver.owner.pm).host names in
  match Array.map (fun (_, v) -> ce c v) fields with
  | [| a; b |] ->
    fun ctx ->
      let x = a ctx in
      let y = b ctx in
      Struct { shape; fields = [| x; y |]; r_owned = true }
  | [| a; b; d; e |] ->
    fun ctx ->
      let x = a ctx in
      let y = b ctx in
      let z = d ctx in
      let w = e ctx in
      Struct { shape; fields = [| x; y; z; w |]; r_owned = true }
  | vals -> fun ctx -> Struct { shape; fields = Array.map (fun v -> v ctx) vals; r_owned = true }

(* User.From, which every struct has: made once, where the code names it. *)
and struct_from c b name =
  match name, b.e with
  | "From", Var { b = Cell { m; k; stable = true }; _ } ->
    (match c.w.modules.(m).cells.(k) with
     | Fun { proto; _ } when Resolve.struct_fields proto.func <> None -> Some (from_native proto c.ver.owner.pm)
     | _ -> None)
  | _ -> None

and field_read c e b name =
  let base = (match leaf c b with `L k -> (fun (ctx : ctx) -> ctx.v.(ctx.b + k)) | l -> leaf_value l) in
  let s = site c e.pos and pm = c.ver.owner.pm in
  (* A single immutable word, replaced at once: correct with several OCaml domains. *)
  let cache = ref { cs = no_shape; ci = 0 } and kcache = ref no_key and key = Text name in
  let h = Trie.hash key in
  fun ctx ->
    match base ctx with
    | Dict { keys; vals; _ } when keys == !kcache.ck -> vals.(!kcache.kc)
    | Struct r ->
      let k = !cache in
      if r.shape == k.cs then r.fields.(k.ci)
      else begin
        ctx.site <- s;
        let i = field_slot ctx pm r.shape name in
        cache := { cs = r.shape; ci = i };
        r.fields.(i)
      end
    | Dict { keys = { deep = Flat; _ } as keys; vals; _ } when Trie.index keys (Array.length vals) h key >= 0 ->
      let i = Trie.index keys (Array.length vals) h key in
      if Trie.is_whole keys then kcache := { ck = keys; kc = i };
      vals.(i)
    | v ->
      ctx.site <- s;
      field_slow ctx pm v name

(* The function of a call x.name(...): what a field holds, or the method of the struct of x and its object. With [shared],
   the object can't be lent: an argument writes, or another fiber can reach it. *)
and member_read c e b name ~shared =
  let base = (match leaf c b with `L k -> (fun (ctx : ctx) -> ctx.v.(ctx.b + k)) | l -> leaf_value l) in
  let s = site c e.pos and pm = c.ver.owner.pm in
  let cache = ref { ms = no_shape; mi = 0; mg = Undef; mr = 0 } and others = ref [] and vias = ref [] in
  let kcache = ref no_key and key = Text name in
  let h = Trie.hash key in
  let keep k =
    if !cache.ms == no_shape || !cache.ms == k.ms then cache := k
    else
      let rest = List.filter (fun o -> o.ms != k.ms) !others in
      if List.compare_length_with rest max_met < 0 then others := k :: rest
  in
  let other (ctx : ctx) shape fields =
    match met shape !others with
    | Some k when k.mi <> -2 || k.mr = ctx.w.reloads -> k
    | _ ->
      ctx.site <- s;
      (* Through an interface, a reload forgets, and what the fields hold chooses at each call when it can change the answer. *)
      let v = via_in shape ctx.w.reloads !vias in
      if v != no_via then { ms = shape; mi = -1; mg = choose ctx v fields name; mr = 0 }
      else
        match member_of ctx pm shape name with
        | Ok k -> keep k; k
        | Error v when List.for_all (fun (_, _, need) -> need = []) v.can ->
          let k = { ms = shape; mi = -2; mg = choose ctx v fields name; mr = v.seen } in
          keep k; k
        | Error v ->
          let rest = List.filter (fun o -> o.vs != shape) !vias in
          if List.compare_length_with rest max_met < 0 then vias := v :: rest;
          { ms = shape; mi = -1; mg = choose ctx v fields name; mr = 0 }
  in
  fun ctx ->
    match base ctx with
    | Struct r as x ->
      let k = !cache in
      if r.shape == k.ms && (k.mi <> -2 || k.mr = ctx.w.reloads) then
        if k.mi >= 0 then r.fields.(k.mi) else Bound { g = k.mg; self = (if shared then Value.share x else x) }
      else begin
        let k = other ctx r.shape r.fields in
        if k.mi >= 0 then r.fields.(k.mi) else Bound { g = k.mg; self = (if shared then Value.share x else x) }
      end
    | Dict { keys; vals; _ } when keys == !kcache.ck -> vals.(!kcache.kc)
    | Dict { keys = { deep = Flat; _ } as keys; vals; _ } when Trie.index keys (Array.length vals) h key >= 0 ->
      let i = Trie.index keys (Array.length vals) h key in
      if Trie.is_whole keys then kcache := { ck = keys; kc = i };
      vals.(i)
    | Dict _ as x ->
      ctx.site <- s;
      map_member ctx pm x name
    | v ->
      ctx.site <- s;
      field_slow ctx pm v name

and match_expr c e subject arms compile_body =
  let v = ce c subject and s = site c e.pos in
  let arms =
    Array.map
      (fun a ->
         let test = pat_test c a.pt in
         let guard = Option.map (cb c) a.guard in
         let body = compile_body a.abody in
         test, guard, body)
      arms
  in
  let n = Array.length arms in
  fun ctx ->
    let x = v ctx in
    ctx.site <- s;
    let rec go k =
      if k >= n then begin
        ctx.site <- s;
        Runtime.fail ctx Type (Messages.no_match (Value.describe x))
      end else begin
        let test, guard, body = arms.(k) in
        if test ctx x && (match guard with None -> true | Some g -> g ctx) then body ctx else go (k + 1)
      end
    in
    go 0

(* A match pattern: binds its names and says whether it accepts the value. *)
and pat_test c (pt : pat) : ctx -> t -> bool =
  let pm = c.ver.owner.pm in
  match pt with
  | Pwild -> fun _ _ -> true
  | Pname n ->
    let set = setter c n in
    fun ctx v ->
      set ctx (Value.share v);
      true
  | Plit e ->
    let lit = cv c e and s = site c e.pos in
    fun ctx v ->
      let x = lit ctx in
      ctx.site <- s;
      Value.equal ctx v x
  | Parray ps ->
    let tests = Array.map (pat_test c) ps in
    let want = Array.length ps in
    fun ctx v ->
      (match v with
       | Array a when a.rows * a.cols = want ->
         let rec go k = k >= want || (tests.(k) ctx (Value.elt a k) && go (k + 1)) in
         go 0
       | _ -> false)
  | Pcons (name, ps) ->
    let tests = Array.map (pat_test c) ps in
    let want = Array.length ps and sname = Some name in
    fun ctx v ->
      (match v with
       | Struct r when Array.length r.fields = want && r.shape.sname = sname ->
         let rec go k = k >= want || (tests.(k) ctx r.fields.(k) && go (k + 1)) in
         go 0
       | _ -> false)
  | Pstruct fs ->
    let tests = Array.map (fun (name, q) -> name, pat_test c q) fs in
    let keyed = Array.map (fun (name, test) -> Text name, Trie.hash (Text name), test) tests in
    let want = Array.length fs in
    fun ctx v ->
      (match v with
       | Struct r ->
         let rec go k =
           k >= want
           || begin
             let name, test = tests.(k) in
             let i = Value.field_index r.shape name in
             i >= 0 && (reach ctx pm r.shape name; test ctx r.fields.(i)) && go (k + 1)
           end
         in
         go 0
       | Dict _ ->
         let rec go k =
           k >= want
           || (let key, h, test = keyed.(k) in
               match Trie.find v h key with Undef -> false | x -> test ctx x && go (k + 1))
         in
         go 0
       | _ -> false)

and end_index c =
  match c.ends with
  | [] -> assert false
  | (slot, d, n) :: _ ->
    fun ctx ->
      (match ctx.v.(ctx.b + slot) with
       | Array a -> Int (if n = 1 then a.rows * a.cols else if d = 0 then a.rows else a.cols)
       | _ -> Int 1)

and unset_error ctx s text =
  ctx.site <- s;
  Runtime.fail ctx Name (Messages.unset text)

and var c e (n : name) =
  match n.b with
  | Local i ->
    let cell = cell_of c i in
    let text = n.text and k = c.map.(i) in
    if cell >= 0 then read_cell c e cell text
    else if c.tv.(i) == TI then fun ctx -> Int (iget ctx k)
    else if c.tv.(i) == TF then fun ctx -> Float (fget ctx k)
    else if c.func.maybe_undef.(i) then begin
      let s = site c e.pos in
      fun ctx ->
        match ctx.v.(ctx.b + k) with
        | Undef -> unset_error ctx s text
        | v -> v
    end else fun ctx -> ctx.v.(ctx.b + k)
  | Cell { m; k; stable = true } -> let v = c.w.modules.(m).cells.(k) in fun _ -> v
  | Cell { m; k; stable = false } ->
    let md = c.w.modules.(m) and s = site c e.pos and text = n.text in
    fun ctx ->
      (match md.cells.(k) with
       | Undef -> unset_error ctx s text
       | v -> v)
  | Unresolved -> assert false

and read_cell c e k text =
  let s = site c e.pos in
  let md = c.w.modules.(c.ver.owner.pm) in
  fun ctx ->
    match md.cells.(k) with
    | Undef -> unset_error ctx s text
    | v -> v

(* An operand: unchecked local variable, constant, or expression. *)
and leaf c (e : expr) =
  match e.e with
  | Var { b = Local i; _ } when plain_local c i -> `L c.map.(i)
  | Lint i -> `K (Int i)
  | Lfloat x -> `K (Float x)
  | _ -> `X (cv c e)

and plain_local c i = (not c.func.maybe_undef.(i)) && cell_of c i < 0 && c.tv.(i) != TI && c.tv.(i) != TF

and leaf_value = function
  | `L i -> fun (ctx : ctx) -> ctx.v.(ctx.b + i)
  | `K v -> fun _ -> v
  | `X f -> f

and binary c e op a b =
  let s = site c e.pos in
  match op with
  | Add when ty c b == TF && ty c a != TF && ty c a != TI ->
    let x = cv c a and f = cf c b in
    fun ctx ->
      let p = x ctx in
      let q = f ctx in
      (match p with
       | Float u -> Float (u +. q)
       | Int u -> Float (float_of_int u +. q)
       | _ -> add_a ctx s p (Float q))
  | Add when ty c a == TF && ty c b != TF && ty c b != TI ->
    let f = cf c a and y = cv c b in
    fun ctx ->
      let p = f ctx in
      let q = y ctx in
      (match q with
       | Float u -> Float (p +. u)
       | Int u -> Float (p +. float_of_int u)
       | _ -> add_a ctx s (Float p) q)
  | Sub when ty c b == TF && ty c a != TF && ty c a != TI ->
    let x = cv c a and f = cf c b in
    fun ctx ->
      let p = x ctx in
      let q = f ctx in
      (match p with
       | Float u -> Float (u -. q)
       | Int u -> Float (float_of_int u -. q)
       | _ -> sub_a ctx s p (Float q))
  | Sub when ty c a == TF && ty c b != TF && ty c b != TI ->
    let f = cf c a and y = cv c b in
    fun ctx ->
      let p = f ctx in
      let q = y ctx in
      (match q with
       | Float u -> Float (p -. u)
       | Int u -> Float (p -. float_of_int u)
       | _ -> sub_a ctx s (Float p) q)
  | Mul when ty c b == TF && ty c a != TF && ty c a != TI ->
    let x = cv c a and f = cf c b in
    fun ctx ->
      let p = x ctx in
      let q = f ctx in
      (match p with
       | Float u -> Float (u *. q)
       | Int u -> Float (float_of_int u *. q)
       | _ -> mul_a ctx s p (Float q))
  | Mul when ty c a == TF && ty c b != TF && ty c b != TI ->
    let f = cf c a and y = cv c b in
    fun ctx ->
      let p = f ctx in
      let q = y ctx in
      (match q with
       | Float u -> Float (p *. u)
       | Int u -> Float (p *. float_of_int u)
       | _ -> mul_a ctx s (Float p) q)
  | Div when ty c b == TF && ty c a != TF && ty c a != TI ->
    let x = cv c a and f = cf c b in
    fun ctx ->
      let p = x ctx in
      let q = f ctx in
      (match p with
       | Float u -> Float (u /. q)
       | Int u -> Float (float_of_int u /. q)
       | _ -> div_a ctx s p (Float q))
  | Div when ty c a == TF && ty c b != TF && ty c b != TI ->
    let f = cf c a and y = cv c b in
    fun ctx ->
      let p = f ctx in
      let q = y ctx in
      (match q with
       | Float u -> Float (p /. u)
       | Int u -> Float (p /. float_of_int u)
       | _ -> div_a ctx s (Float p) q)
  | Add ->
    (match leaf c a, leaf c b with
     | `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in add_a ctx s v.(p + i) v.(p + j)
     | `L i, `K k -> fun ctx -> add_a ctx s ctx.v.(ctx.b + i) k
     | `X f, `L j -> fun ctx -> let x = f ctx in add_a ctx s x ctx.v.(ctx.b + j)
     | `L i, `X f -> fun ctx -> let y = f ctx in add_a ctx s ctx.v.(ctx.b + i) y
     | x, y ->
       let x = leaf_value x and y = leaf_value y in
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         add_a ctx s p q)
  | Sub ->
    (match leaf c a, leaf c b with
     | `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in sub_a ctx s v.(p + i) v.(p + j)
     | `L i, `K k -> fun ctx -> sub_a ctx s ctx.v.(ctx.b + i) k
     | `X f, `L j -> fun ctx -> let x = f ctx in sub_a ctx s x ctx.v.(ctx.b + j)
     | `L i, `X f -> fun ctx -> let y = f ctx in sub_a ctx s ctx.v.(ctx.b + i) y
     | x, y ->
       let x = leaf_value x and y = leaf_value y in
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         sub_a ctx s p q)
  | Mul ->
    (match leaf c a, leaf c b with
     | `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in mul_a ctx s v.(p + i) v.(p + j)
     | `K k, `L j -> fun ctx -> mul_a ctx s k ctx.v.(ctx.b + j)
     | `X f, `L j -> fun ctx -> let x = f ctx in mul_a ctx s x ctx.v.(ctx.b + j)
     | `L i, `X f -> fun ctx -> let y = f ctx in mul_a ctx s ctx.v.(ctx.b + i) y
     | x, y ->
       let x = leaf_value x and y = leaf_value y in
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         mul_a ctx s p q)
  | Div ->
    let x = cv c a and y = cv c b in
    fun ctx ->
      let p = x ctx in
      let q = y ctx in
      div_a ctx s p q
  | Pow ->
    let x = cv c a and y = cv c b in
    slow x y s Arith.pow
  | Eq | Ne | Lt | Le | Gt | Ge ->
    let f =
      match op with
      | Eq -> Arith.eq
      | Ne -> Arith.ne
      | Lt -> Arith.lt
      | Le -> Arith.le
      | Gt -> Arith.gt
      | _ -> Arith.ge
    in
    slow (cv c a) (cv c b) s f

and slow x y s f =
  fun ctx ->
    let p = x ctx in
    let q = y ctx in
    ctx.site <- s;
    f ctx p q

and interp c parts pos =
  let parts =
    Array.map
      (function
        | Lit s -> `Lit s
        | Hole e -> `Hole (cv c e))
      parts
  in
  let s = site c pos in
  fun ctx ->
    let b = Buffer.create 32 in
    Array.iter
      (function
        | `Lit t -> Buffer.add_string b t
        | `Hole f ->
          let v = f ctx in
          ctx.site <- s;
          let text = Value.text_of ctx v in
          Runtime.reserve ctx ((String.length text / 8) + 1);
          Runtime.pay_bytes ctx (String.length text);
          (try Buffer.add_string b text
           with Out_of_memory | Failure _ -> raise (Value.Limit { what = "memory"; at = s })))
      parts;
    Text (Buffer.contents b)

and cb c (e : expr) : ctx -> bool =
  match e.e with
  | Not a ->
    let a = cb c a in
    fun ctx -> not (a ctx)
  | And (a, b) ->
    let a = cb c a and b = cb c b in
    fun ctx -> a ctx && b ctx
  | Or (a, b) ->
    let a = cb c a and b = cb c b in
    fun ctx -> a ctx || b ctx
  | Bin (((Lt | Le | Gt | Ge | Eq | Ne) as op), a, b) ->
    (match ty c a, ty c b with
     | TI, TI -> compare_i c op a b
     | (TI | TF), (TI | TF) -> compare_f c op a b
     | _ -> compare_b c e op a b)
  | Lbool x -> fun _ -> x
  | _ ->
    let v = cv c e and s = site c e.pos in
    fun ctx -> truth s ctx (v ctx)

and compare_i c op a b : ctx -> bool =
  let x = ci c a in
  match op, iint c a, iint c b with
  | Lt, `L p, `L q -> fun ctx -> iget ctx p < iget ctx q
  | Le, `L p, `L q -> fun ctx -> iget ctx p <= iget ctx q
  | Gt, `L p, `L q -> fun ctx -> iget ctx p > iget ctx q
  | Ge, `L p, `L q -> fun ctx -> iget ctx p >= iget ctx q
  | _ ->
  match op, iint c a, b.e with
  | Lt, `L p, Lint k -> fun ctx -> iget ctx p < k
  | Le, `L p, Lint k -> fun ctx -> iget ctx p <= k
  | Gt, `L p, Lint k -> fun ctx -> iget ctx p > k
  | Ge, `L p, Lint k -> fun ctx -> iget ctx p >= k
  | Eq, `L p, Lint k -> fun ctx -> iget ctx p = k
  | Ne, `L p, Lint k -> fun ctx -> iget ctx p <> k
  | _ ->
  match op, b.e with
  | Lt, Lint k -> fun ctx -> x ctx < k
  | Le, Lint k -> fun ctx -> x ctx <= k
  | Gt, Lint k -> fun ctx -> x ctx > k
  | Ge, Lint k -> fun ctx -> x ctx >= k
  | Eq, Lint k -> fun ctx -> x ctx = k
  | Ne, Lint k -> fun ctx -> x ctx <> k
  | _ ->
    let y = ci c b in
    (match op with
     | Lt -> fun ctx -> let p = x ctx in p < y ctx
     | Le -> fun ctx -> let p = x ctx in p <= y ctx
     | Gt -> fun ctx -> let p = x ctx in p > y ctx
     | Ge -> fun ctx -> let p = x ctx in p >= y ctx
     | Eq -> fun ctx -> let p = x ctx in p = y ctx
     | _ -> fun ctx -> let p = x ctx in p <> y ctx)

and compare_f c op a b : ctx -> bool =
  (* A closure returning a float allocates it: read the variables directly. *)
  match op, a.e, b.e with
  | Lt, Bin (Add, { e = Var { b = Local i; _ }; _ }, { e = Var { b = Local j; _ }; _ }), Lfloat k
    when c.tv.(i) == TF && c.tv.(j) == TF && cell_of c i < 0 && cell_of c j < 0 ->
    let p = c.map.(i) and q = c.map.(j) in
    fun ctx -> fget ctx p +. fget ctx q < k
  | _ ->
  match op, fleaf c a, fleaf c b with
  | Lt, `L i, `K k -> fun ctx -> fget ctx i < k
  | Le, `L i, `K k -> fun ctx -> fget ctx i <= k
  | Gt, `L i, `K k -> fun ctx -> fget ctx i > k
  | Ge, `L i, `K k -> fun ctx -> fget ctx i >= k
  | Lt, `L i, `L j -> fun ctx -> fget ctx i < fget ctx j
  | Le, `L i, `L j -> fun ctx -> fget ctx i <= fget ctx j
  | Gt, `L i, `L j -> fun ctx -> fget ctx i > fget ctx j
  | Ge, `L i, `L j -> fun ctx -> fget ctx i >= fget ctx j
  | _ ->
  let x = cf c a in
  match op, b.e with
  | Lt, Lfloat k -> fun ctx -> x ctx < k
  | Le, Lfloat k -> fun ctx -> x ctx <= k
  | Gt, Lfloat k -> fun ctx -> x ctx > k
  | Ge, Lfloat k -> fun ctx -> x ctx >= k
  | _ ->
    let y = cf c b in
    (match op with
     | Lt -> fun ctx -> let p = x ctx in p < y ctx
     | Le -> fun ctx -> let p = x ctx in p <= y ctx
     | Gt -> fun ctx -> let p = x ctx in p > y ctx
     | Ge -> fun ctx -> let p = x ctx in p >= y ctx
     | Eq -> fun ctx -> let p = x ctx in p = y ctx
     | _ -> fun ctx -> let p = x ctx in p <> y ctx)

(* An integer expression. *)
and ci c (e : expr) : ctx -> int =
  match e.e with
  | Lint k -> fun _ -> k
  | Var { b = Local i; _ } when c.tv.(i) == TI && cell_of c i < 0 ->
    let k = c.map.(i) in
    fun ctx -> iget ctx k
  | Bin (Add, { e = Call { callee = { e = Var { b = Cell { m; k; stable = true }; _ }; _ };
                           args = [| { value = { e = Var { b = Local i; _ }; _ }; _ }; { value = { e = Lint d; _ }; _ } |]; _ };
                _ }, { e = Lint q; _ })
    when d > 0 && d land (d - 1) = 0 && c.tv.(i) == TI && cell_of c i < 0
         && (match c.w.modules.(m).cells.(k) with Native { nname = "Mod"; _ } -> true | _ -> false) ->
    (* xs[Mod(i, n) + 1]: the idiom of a 1-indexed language. The result can't overflow while q stays small, which the
       mask guarantees for d and q on 31 bits. *)
    if d < 1 lsl 31 && abs q < 1 lsl 31 then begin
      let p = c.map.(i) and mask = d - 1 in
      fun ctx -> (iget ctx p land mask) + q
    end
    else begin
      let s = site c e.pos and p = c.map.(i) and mask = d - 1 in
      fun ctx -> add_i ctx s (iget ctx p land mask) q
    end
  | Bin (((Add | Sub | Mul) as op), a, b) when ty c a == TI && ty c b == TI ->
    (match super_int c e op a b with
     | Some f -> f
     | None -> int_binary c e op a b)
  | Neg a when ty c a == TI ->
    let s = site c e.pos and x = ci c a in
    fun ctx ->
      let p = x ctx in
      if p = min_int then begin
        ctx.site <- s;
        to_i ctx (Arith.neg ctx (Int p))
      end else -p
  | If ({ e = Bin (Lt, ({ e = Var { b = Local i; _ }; _ } as a), { e = Lint k; _ }); _ }, yes, no)
    when ty c a == TI && cell_of c i < 0 ->
    let p = c.map.(i) and no' = ci_block c no in
    (match yes with
     | [| { e = Var { b = Local j; _ }; _ } |] when c.tv.(j) == TI && cell_of c j < 0 ->
       (* The base case of a recursion: return a variable, without a closure. *)
       let q = c.map.(j) in
       fun ctx -> if iget ctx p < k then iget ctx q else no' ctx
     | _ ->
       let yes = ci_block c yes in
       fun ctx -> if iget ctx p < k then yes ctx else no' ctx)
  | If (cond, yes, no) ->
    let cond = cb c cond and yes = ci_block c yes and no = ci_block c no in
    fun ctx -> if cond ctx then yes ctx else no ctx
  | Return { tail = true; rvalue = Some v } -> ci c v
  | Call { callee = { e = Var { b = Cell { m; k; stable = true }; _ }; _ }; args = [| a; b |]; _ }
    when ty c a.value == TI && ty c b.value == TI
         && (match c.w.modules.(m).cells.(k) with Native { i2 = Some _; _ } -> true | _ -> false) ->
    let n = (match c.w.modules.(m).cells.(k) with Native n -> n | _ -> assert false) in
    let f = Option.get n.i2 in
    (match n.nname, b.value.e with
     | "Mod", Lint d when d > 0 && d land (d - 1) = 0 ->
       (* idiv costs about twenty ns: a mask gives the same downward rounding. *)
       let mask = d - 1 in
       (match iint c a.value with
        | `L p -> fun ctx -> iget ctx p land mask
        | _ ->
          let x = ci c a.value in
          fun ctx -> x ctx land mask)
     | _ ->
       let x = ci c a.value and y = ci c b.value and s = site c e.pos in
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         ctx.site <- s;
         f ctx p q)
  | Call call ->
    (match prepare_call c e call with
     | `Direct (ver, write, off, s) ->
       fun ctx ->
         write ctx;
         let b = ctx.b in
         enter ctx (b + off) s ver;
         let r = ver.ri ctx in
         ctx.b <- b;
         r
     | `Direct1 (ver, a, p, off, s) ->
       fun ctx ->
         let x = a ctx in
         let b = ctx.b and i = ctx.i in
         i.(b + p) <- x;
         enter_fast ctx i b (b + off) s ver;
         let r = ver.ri ctx in
         ctx.b <- b;
         r
     | `Minus1 (ver, q, d, p, off, s, sub) ->
       fun ctx ->
         let b = ctx.b and i = ctx.i in
         let x = (if d > 0 then sub_const ctx sub i.(b + q) d else sub_i ctx sub i.(b + q) d) in
         i.(b + p) <- x;
         enter_fast ctx i b (b + off) s ver;
         let r = ver.ri ctx in
         ctx.b <- b;
         r
     | `Tail jump -> fun ctx -> jump ctx; 0
     | `Other ->
       let v = ca c e in
       fun ctx -> to_i ctx (v ctx))
  | _ ->
    let v = ca c e in
    fun ctx -> to_i ctx (v ctx)

and sop = function
  | Add -> Some Super.Add
  | Sub -> Some Super.Sub
  | Mul -> Some Super.Mul
  | _ -> None

and iint c (e : expr) =
  match e.e with
  | Var { b = Local i; _ } when c.tv.(i) == TI && cell_of c i < 0 -> `L c.map.(i)
  | Lint k -> `K k
  | _ -> `X

and to_il c (e : expr) =
  match iint c e with
  | `L p -> Super.IL p
  | `K k -> Super.IK k
  | `X -> Super.IX (ci c e)

and inner_int c (e : expr) =
  match e.e with
  | Bin (((Add | Sub | Mul) as op), a, b) when ty c a == TI && ty c b == TI && iint c a <> `X && iint c b <> `X ->
    (match iint c a, iint c b with
     | `K _, `K _ -> None
     | _ -> Some (Option.get (sop op), a, b))
  | _ -> None

and super_int c (e : expr) op a b =
  let o2 = Option.get (sop op) in
  match inner_int c a, inner_int c b with
  | Some (o1, x, y), _ ->
    Super.int_left (site c a.pos) (site c e.pos) o1 o2 (to_il c x) (to_il c y) (to_il c b)
  | None, Some (o1, x, y) ->
    Super.int_right (site c b.pos) (site c e.pos) o1 o2 (to_il c a) (to_il c x) (to_il c y)
  | None, None -> None

and int_binary c (e : expr) op a b : ctx -> int =
  let s = site c e.pos in
  match op, iint c a, iint c b with
  | Add, `L p, `K k -> fun ctx -> add_i ctx s (iget ctx p) k
  | Add, `L p, `L q -> fun ctx -> add_i ctx s (iget ctx p) (iget ctx q)
  | Add, `X, `K k -> let x = ci c a in fun ctx -> add_i ctx s (x ctx) k
  | Add, `X, `L q -> let x = ci c a in fun ctx -> let v = x ctx in add_i ctx s v (iget ctx q)
  | Sub, `L p, `K k -> fun ctx -> sub_i ctx s (iget ctx p) k
  | Sub, `L p, `L q -> fun ctx -> sub_i ctx s (iget ctx p) (iget ctx q)
  | Sub, `X, `K k -> let x = ci c a in fun ctx -> sub_i ctx s (x ctx) k
  | Mul, `L p, `L q -> fun ctx -> mul_i ctx s (iget ctx p) (iget ctx q)
  | Mul, `L p, `K k -> fun ctx -> mul_i ctx s (iget ctx p) k
  | Mul, `K k, `L q -> fun ctx -> mul_i ctx s k (iget ctx q)
  | _ ->
    let x = ci c a and y = ci c b in
    (match op with
     | Add ->
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         add_i ctx s p q
     | Sub ->
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         sub_i ctx s p q
     | _ ->
       fun ctx ->
         let p = x ctx in
         let q = y ctx in
         mul_i ctx s p q)

and ci_block c (b : block) : ctx -> int =
  let n = Array.length b in
  if n = 0 then fun _ -> 0
  else if n = 1 then ci c b.(0)
  else begin
    let pre = seq_u (List.map (cu c) (Array.to_list (Array.sub b 0 (n - 1)))) in
    let last = ci c b.(n - 1) in
    fun ctx -> pre ctx; last ctx
  end

(* A float expression, or a converted integer one. *)
and cf c (e : expr) : ctx -> float =
  match e.e with
  | Lfloat x -> fun _ -> x
  | Lint k -> let x = float_of_int k in fun _ -> x
  | _ ->
    match ty c e, iint c e with
    | TI, `L p -> fun ctx -> float_of_int (iget ctx p)
    | TI, _ ->
      let i = ci c e in
      fun ctx -> float_of_int (i ctx)
    | TF, _ -> cff c e
    | _ ->
      let v = ca c e in
      fun ctx -> to_f ctx (v ctx)

and fleaf c (e : expr) =
  match e.e with
  | Var { b = Local i; _ } when c.tv.(i) == TF && cell_of c i < 0 -> `L c.map.(i)
  | Var { b = Local i; _ } when c.tv.(i) == TI && cell_of c i < 0 -> `I c.map.(i)
  | Lfloat x -> `K x
  | Lint k -> `K (float_of_int k)
  | _ -> `X (cf c e)

(* Without the integer leaf, for the forms that have none. *)
and fleaf3 c (e : expr) =
  match fleaf c e with
  | `I p -> `X (fun ctx -> float_of_int (iget ctx p))
  | `L _ as l -> l
  | `K _ as k -> k
  | `X _ as x -> x

and super_float_applies c a b = inner_float c a <> None || inner_float c b <> None

and to_fl c (e : expr) =
  match fleaf3 c e with
  | `L p -> Super.FL p
  | `K k -> Super.FK k
  | `X f -> Super.FX f

and inner_float c (e : expr) =
  match e.e with
  | Bin (((Add | Sub | Mul) as op), a, b) when ty c e == TF ->
    (match fleaf_kind c a, fleaf_kind c b with
     | `X, _ | _, `X | `K, `K -> None
     | _ -> Some (Option.get (sop op), a, b))
  | _ -> None

and fleaf_kind c (e : expr) =
  match e.e with
  | Var { b = Local i; _ } when c.tv.(i) == TF && cell_of c i < 0 -> `L
  | Lfloat _ | Lint _ -> `K
  | _ -> `X

and super_float c op a b =
  let o2 = Option.get (sop op) in
  match inner_float c a, inner_float c b with
  | Some (o1, x, y), _ -> Super.float_left o1 o2 (to_fl c x) (to_fl c y) (to_fl c b)
  | None, Some (o1, x, y) -> Super.float_right o1 o2 (to_fl c a) (to_fl c x) (to_fl c y)
  | None, None -> None

and cff c (e : expr) : ctx -> float =
  match e.e with
  | Var { b = Local i; _ } when c.tv.(i) == TF && cell_of c i < 0 ->
    let k = c.map.(i) in
    fun ctx -> fget ctx k
  | Bin (Mul, { e = Index ({ e = Var { b = Local p; _ }; _ }, [| Ix i |], false); pos = ps; _ },
         { e = Index ({ e = Var { b = Local q; _ }; _ }, [| Ix j |], false); pos = qs; _ })
    when ty c i == TI && ty c j == TI && plain_local c p && plain_local c q ->
    let x = ci c i and y = ci c j and sx = site c ps and sy = site c qs in
    let p = c.map.(p) and q = c.map.(q) in
    fun ctx ->
      let k = x ctx in
      let u = fa_get ctx p k sx in
      let l = y ctx in
      u *. fa_get ctx q l sy
  | Bin (Add, { e = Index ({ e = Var { b = Local p; _ }; _ }, [| Ix i |], false); pos = ps; _ },
         { e = Index ({ e = Var { b = Local q; _ }; _ }, [| Ix j |], false); pos = qs; _ })
    when ty c i == TI && ty c j == TI && plain_local c p && plain_local c q ->
    let x = ci c i and y = ci c j and sx = site c ps and sy = site c qs in
    let p = c.map.(p) and q = c.map.(q) in
    fun ctx ->
      let k = x ctx in
      let u = fa_get ctx p k sx in
      let l = y ctx in
      u +. fa_get ctx q l sy
  | Bin (Sub, { e = Index ({ e = Var { b = Local p; _ }; _ }, [| Ix i |], false); pos = ps; _ },
         { e = Index ({ e = Var { b = Local q; _ }; _ }, [| Ix j |], false); pos = qs; _ })
    when ty c i == TI && ty c j == TI && plain_local c p && plain_local c q ->
    let x = ci c i and y = ci c j and sx = site c ps and sy = site c qs in
    let p = c.map.(p) and q = c.map.(q) in
    fun ctx ->
      let k = x ctx in
      let u = fa_get ctx p k sx in
      let l = y ctx in
      u -. fa_get ctx q l sy
  | Bin (Div, { e = Index ({ e = Var { b = Local p; _ }; _ }, [| Ix i |], false); pos = ps; _ },
         { e = Index ({ e = Var { b = Local q; _ }; _ }, [| Ix j |], false); pos = qs; _ })
    when ty c i == TI && ty c j == TI && plain_local c p && plain_local c q ->
    let x = ci c i and y = ci c j and sx = site c ps and sy = site c qs in
    let p = c.map.(p) and q = c.map.(q) in
    fun ctx ->
      let k = x ctx in
      let u = fa_get ctx p k sx in
      let l = y ctx in
      u /. fa_get ctx q l sy
  | Bin (((Add | Sub | Mul) as op), a, b) when super_float_applies c a b -> Option.get (super_float c op a b)
  | Var { b = Cell { m; k; stable = true }; _ } ->
    (match c.w.modules.(m).cells.(k) with
     | Float x -> fun _ -> x
     | _ -> assert false)
  | Bin (Add, a, b) ->
    (match fleaf c a, fleaf c b with
     | `L i, `L j -> fun ctx -> fget ctx i +. fget ctx j
     | `L i, `K k -> fun ctx -> fget ctx i +. k
     | `K k, `L j -> fun ctx -> k +. fget ctx j
     | `X f, `L j -> fun ctx -> let x = f ctx in x +. fget ctx j
     | `L i, `X g -> fun ctx -> let y = g ctx in fget ctx i +. y
     | `X f, `K k -> fun ctx -> f ctx +. k
     | `K k, `X g -> fun ctx -> k +. g ctx
     | `K k, `K m -> let r = k +. m in fun _ -> r
     | `L i, `I j -> fun ctx -> fget ctx i +. float_of_int (iget ctx j)
     | `I i, `L j -> fun ctx -> float_of_int (iget ctx i) +. fget ctx j
     | `K k, `I j -> fun ctx -> k +. float_of_int (iget ctx j)
     | `I i, `K k -> fun ctx -> float_of_int (iget ctx i) +. k
     | `I i, `I j -> fun ctx -> float_of_int (iget ctx i) +. float_of_int (iget ctx j)
     | `X f, `I j -> fun ctx -> let x = f ctx in x +. float_of_int (iget ctx j)
     | `I i, `X g -> fun ctx -> let y = g ctx in float_of_int (iget ctx i) +. y
     | `X f, `X g ->
       fun ctx ->
         let x = f ctx in
         x +. g ctx)
  | Bin (Sub, a, b) ->
    (match fleaf c a, fleaf c b with
     | `L i, `L j -> fun ctx -> fget ctx i -. fget ctx j
     | `L i, `K k -> fun ctx -> fget ctx i -. k
     | `K k, `L j -> fun ctx -> k -. fget ctx j
     | `X f, `L j -> fun ctx -> let x = f ctx in x -. fget ctx j
     | `L i, `X g -> fun ctx -> let y = g ctx in fget ctx i -. y
     | `X f, `K k -> fun ctx -> f ctx -. k
     | `K k, `X g -> fun ctx -> k -. g ctx
     | `K k, `K m -> let r = k -. m in fun _ -> r
     | `L i, `I j -> fun ctx -> fget ctx i -. float_of_int (iget ctx j)
     | `I i, `L j -> fun ctx -> float_of_int (iget ctx i) -. fget ctx j
     | `K k, `I j -> fun ctx -> k -. float_of_int (iget ctx j)
     | `I i, `K k -> fun ctx -> float_of_int (iget ctx i) -. k
     | `I i, `I j -> fun ctx -> float_of_int (iget ctx i) -. float_of_int (iget ctx j)
     | `X f, `I j -> fun ctx -> let x = f ctx in x -. float_of_int (iget ctx j)
     | `I i, `X g -> fun ctx -> let y = g ctx in float_of_int (iget ctx i) -. y
     | `X f, `X g ->
       fun ctx ->
         let x = f ctx in
         x -. g ctx)
  | Bin (Mul, a, b) ->
    (match fleaf c a, fleaf c b with
     | `L i, `L j -> fun ctx -> fget ctx i *. fget ctx j
     | `L i, `K k -> fun ctx -> fget ctx i *. k
     | `K k, `L j -> fun ctx -> k *. fget ctx j
     | `X f, `L j -> fun ctx -> let x = f ctx in x *. fget ctx j
     | `L i, `X g -> fun ctx -> let y = g ctx in fget ctx i *. y
     | `X f, `K k -> fun ctx -> f ctx *. k
     | `K k, `X g -> fun ctx -> k *. g ctx
     | `K k, `K m -> let r = k *. m in fun _ -> r
     | `L i, `I j -> fun ctx -> fget ctx i *. float_of_int (iget ctx j)
     | `I i, `L j -> fun ctx -> float_of_int (iget ctx i) *. fget ctx j
     | `K k, `I j -> fun ctx -> k *. float_of_int (iget ctx j)
     | `I i, `K k -> fun ctx -> float_of_int (iget ctx i) *. k
     | `I i, `I j -> fun ctx -> float_of_int (iget ctx i) *. float_of_int (iget ctx j)
     | `X f, `I j -> fun ctx -> let x = f ctx in x *. float_of_int (iget ctx j)
     | `I i, `X g -> fun ctx -> let y = g ctx in float_of_int (iget ctx i) *. y
     | `X f, `X g ->
       fun ctx ->
         let x = f ctx in
         x *. g ctx)
  | Bin (Div, a, b) ->
    (match fleaf c a, fleaf c b with
     | `L i, `L j -> fun ctx -> fget ctx i /. fget ctx j
     | `L i, `K k -> fun ctx -> fget ctx i /. k
     | `K k, `L j -> fun ctx -> k /. fget ctx j
     | `X f, `L j -> fun ctx -> let x = f ctx in x /. fget ctx j
     | `L i, `X g -> fun ctx -> let y = g ctx in fget ctx i /. y
     | `X f, `K k -> fun ctx -> f ctx /. k
     | `K k, `X g -> fun ctx -> k /. g ctx
     | `K k, `K m -> let r = k /. m in fun _ -> r
     | `L i, `I j -> fun ctx -> fget ctx i /. float_of_int (iget ctx j)
     | `I i, `L j -> fun ctx -> float_of_int (iget ctx i) /. fget ctx j
     | `K k, `I j -> fun ctx -> k /. float_of_int (iget ctx j)
     | `I i, `K k -> fun ctx -> float_of_int (iget ctx i) /. k
     | `I i, `I j -> fun ctx -> float_of_int (iget ctx i) /. float_of_int (iget ctx j)
     | `X f, `I j -> fun ctx -> let x = f ctx in x /. float_of_int (iget ctx j)
     | `I i, `X g -> fun ctx -> let y = g ctx in float_of_int (iget ctx i) /. y
     | `X f, `X g ->
       fun ctx ->
         let x = f ctx in
         x /. g ctx)
  | Bin (Pow, a, b) ->
    let x = cf c a and y = cf c b in
    fun ctx ->
      let p = x ctx in
      p ** y ctx
  | Neg a ->
    let x = cf c a in
    fun ctx -> -.x ctx
  | If (cond, yes, no) ->
    let cond = cb c cond and yes = cf_block c yes and no = cf_block c no in
    fun ctx -> if cond ctx then yes ctx else no ctx
  | Return { tail = true; rvalue = Some v } -> cf c v
  | Index (b, [| Ix i |], false) -> fa_read1 c e b i
  | Index (b, [| Ix i; Ix j |], false) -> fa_read2 c e b i j
  | Call ({ callee = { e = Var { b = Cell { m; k; stable = true }; _ }; _ }; args = [| a |]; _ })
    when (match c.w.modules.(m).cells.(k) with Native { f1 = Some _; _ } -> true | _ -> false) ->
    let f = (match c.w.modules.(m).cells.(k) with Native { f1 = Some f; _ } -> f | _ -> assert false) in
    let x = cf c a.value in
    fun ctx -> f (x ctx)
  | Call call ->
    (match prepare_call c e call with
     | `Direct (ver, write, off, s) ->
       fun ctx ->
         write ctx;
         let b = ctx.b in
         enter ctx (b + off) s ver;
         let r = ver.rf ctx in
         ctx.b <- b;
         r
     | `Direct1 (ver, a, p, off, s) ->
       fun ctx ->
         let x = a ctx in
         let b = ctx.b and i = ctx.i in
         i.(b + p) <- x;
         enter_fast ctx i b (b + off) s ver;
         let r = ver.rf ctx in
         ctx.b <- b;
         r
     | `Minus1 (ver, q, d, p, off, s, sub) ->
       fun ctx ->
         let b = ctx.b and i = ctx.i in
         let x = (if d > 0 then sub_const ctx sub i.(b + q) d else sub_i ctx sub i.(b + q) d) in
         i.(b + p) <- x;
         enter_fast ctx i b (b + off) s ver;
         let r = ver.rf ctx in
         ctx.b <- b;
         r
     | `Tail jump -> fun ctx -> jump ctx; 0.
     | `Other ->
       let v = ca c e in
       fun ctx -> to_f ctx (v ctx))
  | _ ->
    let v = ca c e in
    fun ctx -> to_f ctx (v ctx)

and cf_block c (b : block) : ctx -> float =
  let n = Array.length b in
  if n = 0 then fun _ -> 0.
  else if n = 1 then cf c b.(0)
  else begin
    let pre = seq_u (List.map (cu c) (Array.to_list (Array.sub b 0 (n - 1)))) in
    let last = cf c b.(n - 1) in
    fun ctx -> pre ctx; last ctx
  end

(* Reading an element of an FA array: the index is an integer, the read allocates nothing. *)
and fa_read1 c e b i =
  let idx = ci c i and s = site c e.pos in
  match leaf c b with
  | `L slot ->
    fun ctx ->
      let k = idx ctx in
      (match ctx.v.(ctx.b + slot) with
       | Array { store = F d; rows; cols; _ } when k >= 1 && k <= rows * cols -> Float.Array.get d (k - 1)
       | x ->
         ctx.site <- s;
         to_f ctx (Arrays.read1 ctx x (Arrays.At k)))
  | _ ->
  let base = cv c b in
  fun ctx ->
    let x = base ctx in
    let k = idx ctx in
    match x with
    | Array { store = F d; rows; cols; _ } when k >= 1 && k <= rows * cols -> Float.Array.get d (k - 1)
    | _ ->
      ctx.site <- s;
      to_f ctx (Arrays.read1 ctx x (Arrays.At k))

and fa_read2 c e b i j =
  let base = cv c b and ix = ci c i and jx = ci c j and s = site c e.pos in
  fun ctx ->
    let x = base ctx in
    let p = ix ctx in
    let q = jx ctx in
    match x with
    | Array { store = F d; rows; cols; _ } when p >= 1 && p <= rows && q >= 1 && q <= cols ->
      Float.Array.get d (((q - 1) * rows) + p - 1)
    | _ ->
      ctx.site <- s;
      to_f ctx (Arrays.read2 ctx x (Arrays.At p) (Arrays.At q))

(* A comparison in a condition: no allocation. *)
and compare_b c e op a b =
  let s = site c e.pos in
  let x = leaf c a and y = leaf c b in
  match op, x, y with
  | Gt, `L i, `K (Float k as q) ->
    fun ctx ->
      (match ctx.v.(ctx.b + i) with
       | Float u -> u > k
       | p -> gt_b ctx s p q)
  | Lt, `L i, `K (Float k as q) ->
    fun ctx ->
      (match ctx.v.(ctx.b + i) with
       | Float u -> u < k
       | p -> lt_b ctx s p q)
  | Lt, `L i, `K k -> fun ctx -> lt_b ctx s ctx.v.(ctx.b + i) k
  | Lt, `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in lt_b ctx s v.(p + i) v.(p + j)
  | Le, `L i, `K k -> fun ctx -> le_b ctx s ctx.v.(ctx.b + i) k
  | Le, `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in le_b ctx s v.(p + i) v.(p + j)
  | Gt, `L i, `K k -> fun ctx -> gt_b ctx s ctx.v.(ctx.b + i) k
  | Gt, `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in gt_b ctx s v.(p + i) v.(p + j)
  | Ge, `L i, `K k -> fun ctx -> ge_b ctx s ctx.v.(ctx.b + i) k
  | Ge, `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in ge_b ctx s v.(p + i) v.(p + j)
  | Eq, `L i, `K k -> fun ctx -> eq_b ctx s ctx.v.(ctx.b + i) k
  | Eq, `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in eq_b ctx s v.(p + i) v.(p + j)
  | Ne, `L i, `K k -> fun ctx -> ne_b ctx s ctx.v.(ctx.b + i) k
  | Ne, `L i, `L j -> fun ctx -> let v = ctx.v and p = ctx.b in ne_b ctx s v.(p + i) v.(p + j)
  | _ ->
    let x = leaf_value x and y = leaf_value y in
    (match op with
     | Lt -> fun ctx -> let p = x ctx in let q = y ctx in lt_b ctx s p q
     | Le -> fun ctx -> let p = x ctx in let q = y ctx in le_b ctx s p q
     | Gt -> fun ctx -> let p = x ctx in let q = y ctx in gt_b ctx s p q
     | Ge -> fun ctx -> let p = x ctx in let q = y ctx in ge_b ctx s p q
     | Eq -> fun ctx -> let p = x ctx in let q = y ctx in eq_b ctx s p q
     | _ -> fun ctx -> let p = x ctx in let q = y ctx in ne_b ctx s p q)

and setter c (n : name) : ctx -> t -> unit =
  match n.b with
  | Local i ->
    let cell = cell_of c i and k = c.map.(i) in
    if cell >= 0 then begin
      let md = c.w.modules.(c.ver.owner.pm) in
      fun _ x -> md.cells.(cell) <- x
    end
    else if c.tv.(i) == TI then fun ctx x -> ctx.i.(ctx.b + k) <- to_i ctx x
    else if c.tv.(i) == TF then fun ctx x -> Float.Array.set ctx.f (ctx.b + k) (to_f ctx x)
    else fun ctx x -> ctx.v.(ctx.b + k) <- x
  | Cell _ | Unresolved -> assert false

and write_var c (n : name) (v : ctx -> t) : ctx -> unit =
  let set = setter c n in
  fun ctx ->
    let x = v ctx in
    set ctx x

and cu c (e : expr) : ctx -> unit =
  match e.e with
  | Hook h ->
    c.live <- h.live;
    c.w.hook_count <- c.w.hook_count + 1;
    let s = site c e.pos in
    fun ctx -> ctx.w.on_hook ctx s
  | Assign ({ b = Local i; _ }, v) -> store_var c i v
  | If ({ e = Bin (Gt, ({ e = Var { b = Local i; _ }; _ } as a), { e = Lfloat k; _ }); pos; _ }, yes, [||])
    when plain_local c i && ty c a != TFA ->
    (* The test and the branch in the same closure. *)
    let p = c.map.(i) and q = Float k and s = site c pos and yes = cublock c yes in
    fun ctx ->
      (match ctx.v.(ctx.b + p) with
       | Float u -> if u > k then yes ctx
       | x -> if gt_b ctx s x q then yes ctx)
  | If (cond, yes, [||]) ->
    let cond = cb c cond and yes = cublock c yes in
    fun ctx -> if cond ctx then yes ctx
  | If (cond, yes, no) ->
    let cond = cb c cond and yes = cublock c yes and no = cublock c no in
    fun ctx -> if cond ctx then yes ctx else no ctx
  | Destructure (pt, v) ->
    let v = ce c v and bind = cpat c pt e.pos in
    fun ctx -> bind ctx (v ctx)
  | For { var = { b = Local i; _ }; iter = { e = Range (a, b); pos; _ }; fbody; f_break }
    when c.tv.(i) == TI && cell_of c i < 0 ->
    let l = bound c a pos and h = bound c b pos and body = cublock c fbody and k = c.map.(i) in
    let off = c.off in
    let run ctx =
      let lo = l ctx in
      let hi = h ctx in
      for n = lo to hi do
        ctx.i.(ctx.b + k) <- n;
        body ctx;
        tick ctx off
      done
    in
    if f_break then (fun ctx -> try run ctx with Break_loop -> ()) else run
  | For { var; iter; fbody; f_break } ->
    let body = cublock c fbody in
    let run = loop_over c iter (setter c var) (fun () ctx -> body ctx) () in
    if f_break then (fun ctx -> try run ctx with Break_loop -> ()) else run
  | Set { root; path; value } -> set_path c e root path value
  | While { cond; body; has_break } ->
    let cond = cb c cond and body = cublock c body in
    let off = c.off in
    let run ctx =
      while cond ctx do
        body ctx;
        tick ctx off
      done
    in
    if has_break then (fun ctx -> try run ctx with Break_loop -> ()) else run
  | Break -> fun _ -> raise_notrace Break_loop
  | Fn_def ({ b = Cell _; _ }, _) | Use _ | Interface _ -> fun _ -> ()
  | Fn_def (n, f) ->
    let make = closure c f in
    let self =
      match n.b with
      | Local i -> List.filter_map (fun (j, (outer, _)) -> if outer = i then Some j else None)
                     (List.mapi (fun j p -> j, p) (Array.to_list f.captures))
      | _ -> []
    in
    write_var c n (fun ctx ->
        match make ctx with
        | Fun { env; _ } as g -> List.iter (fun j -> env.(j) <- g) self; g
        | g -> g)
  | _ ->
    let v = cv c e in
    fun ctx -> ignore (v ctx)

(* Writing to a path: evaluate everything, then make each level owned on the way down. *)
and set_path c e root path value =
  let fa =
    match root.b with
    | Local i -> c.tv.(i) == TFA && cell_of c i < 0 && (ty c value == TF || ty c value == TI)
    | _ -> false
  in
  match path with
  | [| { sp; sk = Sindex ([| Ix i |], false) } |] when fa && ty c i == TI -> fa_write1 c root sp i value
  | [| { sp; sk = Sindex ([| Ix i; Ix j |], false) } |] when fa && ty c i == TI && ty c j == TI ->
    fa_write2 c root sp i j value
  | [| { sp; sk = Sindex ([| Ix ({ e = (Var _ | Lint _ | Bin _); _ } as ix) |], false) } |] -> set_elt c e root sp ix value
  | [| { sp; sk = Sfield name } |] -> set_name c root sp name value ~key:false
  | [| { sp; sk = Sindex ([| Ix { e = Ltext name; _ } |], false) } |] -> set_name c root sp name value ~key:true
  | _ -> set_general c e root path value

(* x[i] = f on an owned FA array: neither allocation nor conversion. *)
and fa_write1 c root sp i value =
  let pm = c.ver.owner.pm in
  let idx = ci c i and v = cf c value and s = site c sp in
  let k = (match root.b with Local r -> c.map.(r) | _ -> assert false) in
  let set = setter c root in
  fun ctx ->
    let p = idx ctx in
    let y = v ctx in
    match ctx.v.(ctx.b + k) with
    | Array { store = F d; a_owned = true; rows; cols; _ } when p >= 1 && p <= rows * cols ->
      Float.Array.set d (p - 1) y
    | x ->
      ctx.site <- s;
      write_root ctx pm set x (Rindex [| Arrays.At p |]) (Float y)

and fa_write2 c root sp i j value =
  let pm = c.ver.owner.pm in
  let ix = ci c i and jx = ci c j and v = cf c value and s = site c sp in
  let k = (match root.b with Local r -> c.map.(r) | _ -> assert false) in
  let set = setter c root in
  fun ctx ->
    let p = ix ctx in
    let q = jx ctx in
    let y = v ctx in
    match ctx.v.(ctx.b + k) with
    | Array { store = F d; a_owned = true; rows; cols; _ } when p >= 1 && p <= rows && q >= 1 && q <= cols ->
      Float.Array.set d (((q - 1) * rows) + p - 1) y
    | x ->
      ctx.site <- s;
      write_root ctx pm set x (Rindex [| Arrays.At p; Arrays.At q |]) (Float y)

(* x[i] = y in an owned array: no index allocation. *)
and set_elt c e root sp ix value =
  let pm = c.ver.owner.pm in
  let read = var c { id = 0; pos = sp; e = Var root } root in
  let v = ce c value and s = site c sp in
  let set = setter c root in
  ignore e;
  if ty c ix == TI then begin
    let idx = ci c ix in
    fun ctx ->
      let k = idx ctx in
      let y = v ctx in
      let x = read ctx in
      match x with
      | Array ({ a_owned = true; _ } as a) when k >= 1 && k <= a.rows * a.cols -> Arrays.store_elt ctx s a (k - 1) y
      | _ ->
        ctx.site <- s;
        write_root ctx pm set x (Rindex [| Arrays.At k |]) y
  end else
  let idx = cv c ix in
  fun ctx ->
    let i = idx ctx in
    let y = v ctx in
    let x = read ctx in
    match x, i with
    | Array ({ a_owned = true; _ } as a), Int k when k >= 1 && k <= a.rows * a.cols -> Arrays.store_elt ctx s a (k - 1) y
    | _ ->
      ctx.site <- s;
      write_root ctx pm set x (Rindex [| Arrays.ix_of ctx i |]) y

(* m.Name = x and m["Name"] = x: an owned map of one block writes in place, and a new name gives keys that the site keeps, so
   that the maps that go through it share them, and the reads after it keep their caches. Anything else goes the general way. *)
and set_name c root sp name value ~key =
  let pm = c.ver.owner.pm in
  let read = var c { id = 0; pos = sp; e = Var root } root in
  let set = setter c root in
  let v = ce c value and s = site c sp in
  let k = Text name in
  let h = Trie.hash k in
  let st = if key then Rkey name else Rfield name in
  (* [grown]: the keys of [n] that came here last, and what the name made of them. *)
  let here = ref no_key and grown = ref (no_key.ck, -1, no_key.ck) in
  fun ctx ->
    let y = v ctx in
    let x = read ctx in
    match x with
    | Dict ({ keys = { deep = Flat; _ }; d_owned = true; _ } as d) when d.keys == !here.ck -> d.vals.(!here.kc) <- y
    | Dict ({ keys = { deep = Flat; _ }; d_owned = true; _ } as d) when Trie.index d.keys (Array.length d.vals) h k >= 0 ->
      let i = Trie.index d.keys (Array.length d.vals) h k in
      if Trie.is_whole d.keys then here := { ck = d.keys; kc = i };
      d.vals.(i) <- y
    | Dict ({ keys = { deep = Flat; _ }; d_owned = true; _ } as d) when Array.length d.vals < Trie.width ->
      let n = Array.length d.vals in
      let before, m, after = !grown in
      let after =
        if d.keys == before && m = n then after
        else begin
          let after = Trie.extend d.keys n k h in
          grown := (d.keys, n, after);
          after
        end
      in
      set ctx (Dict { keys = after; vals = Trie.append d.vals y; d_owned = true })
    | _ ->
      ctx.site <- s;
      write_root ctx pm set x st y

and set_general c _e root path value =
  let pm = c.ver.owner.pm in
  let read = var c { id = 0; pos = path.(0).sp; e = Var root } root in
  let set = setter c root in
  let v = ce c value in
  let n = Array.length path in
  let steps =
    Array.map
      (fun { sp; sk } ->
         let s = site c sp in
         match sk with
         | Sfield name -> s, `Field name
         | Sindex ([| Ix { e = Ltext k; _ } |], false) -> s, `Key k
         | Sindex (ixs, uses_end) ->
           let slot, args =
             with_end c uses_end (fun slot ->
                 let saved = c.ends in
                 let count = Array.length ixs in
                 let args =
                   Array.mapi
                     (fun d ix ->
                        c.ends <- (slot, d, count) :: saved;
                        index_arg c ix sp)
                     ixs
                 in
                 c.ends <- saved;
                 slot, args)
           in
           s, `Index (slot, args))
      path
  in
  fun ctx ->
    let root_value = read ctx in
    let cur = ref root_value in
    let resolved =
      Array.mapi
        (fun k (s, step) ->
           let st =
             match step with
             | `Field name -> Rfield name
             | `Key k -> Rkey k
             | `Index (slot, args) ->
               if slot >= 0 then ctx.v.(ctx.b + slot) <- !cur;
               Rindex (Array.map (fun a -> a ctx) args)
           in
           if k < n - 1 then begin
             ctx.site <- s;
             cur := step_read ctx pm !cur st
           end;
           s, st)
        steps
    in
    let y = v ctx in
    ctx.site <- fst steps.(0);
    let container = ref (Runtime.own ctx root_value) in
    let chain = ref [] in
    for k = 0 to n - 2 do
      let s, st = resolved.(k) in
      ctx.site <- s;
      let child = step_read ctx pm !container st in
      chain := (!container, st, s, child) :: !chain;
      container := Runtime.own ctx child
    done;
    let s, st = resolved.(n - 1) in
    ctx.site <- s;
    (* A copied child, a struct with a new field and a dictionary all change their parent, up to the root. A child written in
       place stays in its field, whose type is checked again: an interface depends on what the child holds. *)
    let rec climb value = function
      | [] -> value
      | (parent, st, s, child) :: rest ->
        if value == child then begin
          (match parent, st with
           | Struct r, Rfield name when Array.length r.shape.checks > 0 ->
             ctx.site <- s;
             ignore (checked ctx r.shape (Value.field_index r.shape name) value)
           | _ -> ());
          climb parent rest
        end else begin
          ctx.site <- s;
          climb (step_write ctx pm parent st value) rest
        end
    in
    let top = climb (step_write ctx pm !container st y) !chain in
    if top != root_value then set ctx top

(* Binds a destructuring pattern: a failure is an error. *)
and cpat c (pt : pat) pos : ctx -> t -> unit =
  let pm = c.ver.owner.pm in
  let s = site c pos in
  match pt with
  | Pwild | Plit _ -> fun _ _ -> ()
  | Pname n -> setter c n
  | Parray ps ->
    let binds = Array.map (fun q -> cpat c q pos) ps in
    let want = Array.length ps in
    fun ctx v ->
      (match v with
       | Array a when a.rows * a.cols = want ->
         Array.iteri (fun k b -> b ctx (Value.share (Value.elt a k))) binds
       | Array a ->
         ctx.site <- s;
         Runtime.fail ctx Index (Messages.destructure_array want (a.rows * a.cols))
       | _ ->
         ctx.site <- s;
         Runtime.fail ctx Type (Messages.destructure_value (Value.describe v)))
  | Pcons (name, ps) ->
    let binds = Array.map (fun q -> cpat c q pos) ps in
    let want = Array.length ps and sname = Some name in
    fun ctx v ->
      (match v with
       | Struct r when Array.length r.fields = want && r.shape.sname = sname ->
         Array.iteri (fun k b -> b ctx (Value.share r.fields.(k))) binds
       | _ ->
         ctx.site <- s;
         Runtime.fail ctx Field (Messages.pattern_mismatch name (Value.describe v)))
  | Pstruct fs ->
    let binds = Array.map (fun (name, q) -> name, cpat c q pos) fs in
    fun ctx v ->
      (match v with
       | Struct _ | Dict _ ->
         ctx.site <- s;
         Array.iter (fun (name, b) -> b ctx (Value.share (field_slow ctx pm v name))) binds
       | _ ->
         ctx.site <- s;
         Runtime.fail ctx Type (Messages.destructure_struct (Value.describe v)))

and cublock c (b : block) : ctx -> unit = seq_u (List.map (cu c) (Array.to_list b))

and cblock c (b : block) : ctx -> t =
  let n = Array.length b in
  if n = 0 then fun _ -> Missing
  else if n = 1 then cv c b.(0)
  else begin
    let pre = seq_u (List.map (cu c) (Array.to_list (Array.sub b 0 (n - 1)))) in
    let last = cv c b.(n - 1) in
    fun ctx -> pre ctx; last ctx
  end

and closure c (f : func) : ctx -> t =
  let proto = new_proto ~file:c.file ~m:c.ver.owner.pm f in
  if Array.length f.captures = 0 then begin
    let v = Fun { proto; env = [||] } in
    fun _ -> v
  end else begin
    let reads =
      Array.map
        (fun (outer, _) ->
           let cell = cell_of c outer and k = c.map.(outer) in
           if cell >= 0 then begin
             let md = c.w.modules.(c.ver.owner.pm) in
             fun _ -> md.cells.(cell)
           end
           else if c.tv.(outer) == TI then fun ctx -> Int (iget ctx k)
           else if c.tv.(outer) == TF then fun ctx -> Float (fget ctx k)
           else fun ctx -> ctx.v.(ctx.b + k))
        f.captures
    in
    fun ctx -> Fun { proto; env = Array.map (fun r -> Value.share (r ctx)) reads }
  end

(* A call: direct to a version, tail jump, or something else. *)
and prepare_call ?(target = -1) c (e : expr) (call : call) =
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; _ } ->
    (match c.w.modules.(m).cells.(k) with
     | Fun { proto; env = [||] } ->
       (match Infer.bind_args proto.func call.args with
        | Error _ -> `Other
        | Ok slots ->
          let sg =
            Array.map
              (function
                | None -> TBot
                | Some a -> (match ty c a with TBot -> TA | t -> t))
              slots
          in
          let ver = Infer.version_for c.w proto sg in
          Infer.run c.w ver;
          if call.self_tail && ver == c.ver then `Tail (tail_jump c ver slots)
          else begin
            let np = Array.length slots in
            let off = c.off in
            c.top <- max c.top (off + np + 2);
            c.off <- off + np + 2;
            let modes = passes c (Resolve.keeps proto.func) (fun _ i -> i = target) slots in
            let write = arg_writers c off ver modes slots in
            c.off <- off;
            `Direct (ver, write, off, site c e.pos)
          end)
     | _ -> `Other)
  | _ -> `Other

and call_any ?(target = -1) c e (call : call) : ctx -> t =
  match prepare_call ~target c e call with
  | `Direct (ver, write, off, s) ->
    fun ctx ->
      write ctx;
      let b = ctx.b in
      enter ctx (b + off) s ver;
      let r = ver.rv ctx in
      ctx.b <- b;
      r
  | `Direct1 (ver, a, p, off, s) ->
    fun ctx ->
      let x = a ctx in
      let b = ctx.b and i = ctx.i in
      i.(b + p) <- x;
      enter_fast ctx i b (b + off) s ver;
      let r = ver.rv ctx in
      ctx.b <- b;
      r
  | `Minus1 (ver, q, d, p, off, s, sub) ->
    fun ctx ->
      let b = ctx.b and i = ctx.i in
      let x = (if d > 0 then sub_const ctx sub i.(b + q) d else sub_i ctx sub i.(b + q) d) in
      i.(b + p) <- x;
      enter_fast ctx i b (b + off) s ver;
      let r = ver.rv ctx in
      ctx.b <- b;
      r
  | `Tail jump ->
    fun ctx ->
      jump ctx;
      Missing
  | `Other -> ccall c e call target

(* Tail recursion: the arguments go to the outgoing area, then onto the parameters. The frame ends with the jump, so a
   local variable is given. A parameter is too if it stays in its place: elsewhere, it could reach a kept one. *)
and tail_jump c ver slots : ctx -> unit =
  let np = Array.length slots in
  let off = c.off in
  c.top <- max c.top (off + np + 2);
  c.off <- off + np + 2;
  let modes = passes c (Resolve.keeps ver.owner.func) (fun k i -> i = k || i >= np) slots in
  let write = arg_writers c off ver modes slots in
  c.off <- off;
  let moves =
    List.init np (fun k ->
        let p = ver.map.(k) in
        match ver.tv.(k) with
        | TI -> fun (ctx : ctx) -> ctx.i.(ctx.b + p) <- ctx.i.(ctx.b + off + p)
        | TF -> fun ctx -> Float.Array.set ctx.f (ctx.b + p) (Float.Array.get ctx.f (ctx.b + off + p))
        | _ -> fun ctx -> ctx.v.(ctx.b + p) <- ctx.v.(ctx.b + off + p))
  in
  let move = seq_u moves in
  fun ctx ->
    write ctx;
    move ctx;
    ctx.again <- true

and ccall c e (call : call) target =
  let s = site c e.pos in
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; _ } ->
    (match c.w.modules.(m).cells.(k) with
     | Native n -> call_native c s n call.args
     | Fun { proto; env = [||] } ->
       (match Infer.bind_args proto.func call.args with
        | Error msg -> raise_at s Type msg
        | Ok _ -> call_dynamic c s call target)
     | _ -> call_dynamic c s call target)
  | _ -> call_dynamic c s call target

and raise_at s kind m = fun ctx ->
  ctx.site <- s;
  Runtime.fail ctx kind m

(* Places named arguments by the parameters of a native. A gap stays Undef, which the native reads as absent. *)
and native_args c (n : native) (args : arg array) : (ctx -> t) array =
  let names = Array.map (fun (a : arg) -> a.aname) args in
  if Array.for_all Option.is_none names then Array.map (fun (a : arg) -> cv c a.value) args
  else begin
    let position i (a : arg) =
      match a.aname with
      | None -> i
      | Some name ->
        (match Array.find_index (String.equal name) n.params with
         | Some k -> k
         | None -> raise (Bad_arg (Messages.unknown_arg n.nname name)))
    in
    let placed = Array.mapi (fun i a -> position i a, a) args in
    let size = Array.fold_left (fun acc (k, _) -> max acc (k + 1)) 0 placed in
    let out = Array.make size (fun _ -> Undef) in
    Array.iter (fun (k, (a : arg)) -> out.(k) <- cv c a.value) placed;
    out
  end

and call_native c s n args =
  match native_args c n args with
  | exception Bad_arg m -> raise_at s Type m
  | compiled -> call_native_placed s n compiled

and call_native_placed s n compiled =
  let nargs = Array.length compiled in
  if nargs < n.min_args || nargs > n.max_args then begin
    let want =
      if n.min_args = n.max_args then Printf.sprintf "%d arguments" n.min_args
      else Printf.sprintf "%d to %d arguments" n.min_args n.max_args
    in
    raise_at s Type (Messages.arg_count n.nname want nargs)
  end else begin
    let run =
      match n.perm with
      | None -> n.run
      | Some p ->
        let inner = n.run in
        fun ctx a ->
          Runtime.check_perm ctx p None;
          inner ctx a
    in
    match compiled with
    | [| a |] ->
      fun ctx ->
        let x = a ctx in
        ctx.site <- s;
        run ctx [| x |]
    | [| a; b |] ->
      fun ctx ->
        let x = a ctx in
        let y = b ctx in
        ctx.site <- s;
        run ctx [| x; y |]
    | positional ->
      fun ctx ->
        let vals = Array.map (fun a -> a ctx) positional in
        ctx.site <- s;
        run ctx vals
  end

(* How each argument of a call is passed. [keeps k] says that parameter [k] can't be lent, [gives k i] that variable [i],
   as argument [k], ends with the call. An argument that mentions a given variable shares what it reads. A write among
   the arguments keeps them all shared: an earlier argument must not see it. *)
and passes c keeps gives (slots : expr option array) =
  let args = List.filter_map Fun.id (Array.to_list slots) in
  let given k (e : expr) =
    let i = bare e in
    i >= 0 && plain_local c i && gives k i && List.length (List.filter (fun a -> bare a = i) args) = 1
  in
  let gone =
    Array.to_seqi slots
    |> Seq.filter_map (fun (k, slot) -> Option.bind slot (fun e -> if given k e then Some (bare e) else None))
    |> List.of_seq
  in
  let written = List.exists writes args in
  Array.mapi
    (fun k slot ->
       match slot with
       | Some e when not written ->
         if given k e then Give
         else if keeps k || reads_module e || List.exists (fun i -> mentions i e) gone then Share
         else Lend
       | _ -> Share)
    slots

and read_arg c mode e = if mode = Share then ce c e else cv c e

(* The arguments a dynamic call can lend. A given variable has no bit: the function can do what it wants with it. *)
and lent_bits modes =
  Array.fold_left (fun (bits, k) mode -> (if mode = Lend then bits lor (1 lsl k) else bits), k + 1) (0, 0) modes |> fst

(* Writes the arguments of a direct call to the stacks the version expects. *)
and arg_writers c off (ver : version) modes (slots : expr option array) : ctx -> unit =
  let writer k =
    let p = off + ver.map.(k) in
    match slots.(k) with
    | Some e ->
      (match ver.tv.(k) with
       | TI ->
         let a = ci c e in
         fun (ctx : ctx) ->
           let x = a ctx in
           ctx.i.(ctx.b + p) <- x
       | TF ->
         let a = cf c e in
         fun ctx ->
           let x = a ctx in
           Float.Array.set ctx.f (ctx.b + p) x
       | _ ->
         let a = read_arg c modes.(k) e in
         fun ctx ->
           let x = a ctx in
           ctx.v.(ctx.b + p) <- x)
    | None ->
      if ver.sg.(k) == TBot then fun _ -> ()
      else fun ctx -> ctx.v.(ctx.b + p) <- Undef
  in
  match slots with
  | [| _ |] -> writer 0
  | [| _; _ |] ->
    let a = writer 0 in
    let d = writer 1 in
    fun ctx -> a ctx; d ctx
  | _ -> seq_u (List.init (Array.length slots) writer)

and call_dynamic c s (call : call) target =
  let args = call.args in
  let callee, target, room =
    match call.callee.e with
    | Field (b, name) when struct_from c b name <> None -> (let v = Option.get (struct_from c b name) in fun _ -> v), target, 0
    | Field (b, name) ->
      (* The object is a parameter too: a variable given as an argument must not also be the object. *)
      let shared = reads_module b || Array.exists (fun (a : arg) -> writes a.value) args in
      member_read c call.callee b name ~shared, (if target >= 0 && mentions target b then -1 else target), 1
    | _ -> cv c call.callee, target, 0
  in
  let n = Array.length args in
  let names = Array.map (fun a -> a.aname) args in
  let plain = Array.for_all (fun a -> a = None) names in
  let slots = Array.map (fun a -> Some a.value) args in
  let modes = passes c (fun k -> k >= 62 || not plain) (fun _ i -> i = target) slots in
  if plain && n <= 3 && (n >= 1 || room = 1) then call_small c s callee slots modes room
  else
  let off = c.off in
  c.top <- max c.top (off + n + 2);
  c.off <- off + n + 2;
  let write =
    seq_u
      (List.init n (fun k ->
           let a = read_arg c modes.(k) args.(k).value in
           fun (ctx : ctx) ->
             let x = a ctx in
             ctx.v.(ctx.b + off + k) <- x))
  in
  c.off <- off;
  let lent = lent_bits modes in
  fun ctx ->
    let g = callee ctx in
    write ctx;
    ctx.site <- s;
    if plain then begin
      share_kept ctx g (ctx.b + off) n lent;
      dispatch ctx g off n s
    end
    else dispatch_named ctx g off names s

(* A dynamic call with 1 to 3 arguments: they stay in OCaml variables until the version is chosen, and only those of
   type A go through the v stack, where each write costs a caml_modify. A call x.name() can also have none. [room] makes
   room for the object of a method. *)
and call_small c s callee slots modes room =
  let off = c.off in
  let n = Array.length slots in
  c.top <- max c.top (off + n + room + 2);
  c.off <- off + n + 2;
  (* A local variable argument is read without a closure: slot >= 0. *)
  let source k =
    let e = Option.get slots.(k) in
    match e.e with
    | Var { b = Local i; _ } when plain_local c i && modes.(k) <> Share -> c.map.(i), (fun _ -> Undef)
    | _ -> -1, read_arg c modes.(k) e
  in
  let sa, a = if n > 0 then source 0 else -1, (fun _ -> Undef) in
  let sd, d = if n > 1 then source 1 else -1, (fun _ -> Undef) in
  let sf, f = if n > 2 then source 2 else -1, (fun _ -> Undef) in
  c.off <- off;
  let no_spec = c.w.no_spec in
  let lent = lent_bits modes in
  let others (ctx : ctx) g x y z =
    let bits = match g with Bound _ -> args_kept g land lent | _ -> lent in
    share_if bits 0 x;
    share_if bits 1 y;
    share_if bits 2 z;
    let nb = ctx.b + off in
    if nb + n + 2 > ctx.cap then Runtime.grow ctx (nb + n + 2);
    if n > 0 then ctx.v.(nb) <- x;
    if n > 1 then ctx.v.(nb + 1) <- y;
    if n > 2 then ctx.v.(nb + 2) <- z;
    dispatch ctx g off n s
  in
  (* A method with exactly these arguments: as a call of a function, with the object first. *)
  let slow (ctx : ctx) g x y z =
    match g with
    | Bound { g = Fun { proto; env }; self } when proto.arity = n + 1 ->
      share_if proto.func.kept 0 self;
      let bits = args_kept g land lent in
      share_if bits 0 x;
      share_if bits 1 y;
      share_if bits 2 z;
      let tag =
        if no_spec then no_tag
        else
          arg_type self
          lor (if n > 0 then arg_type x lsl 2 else 0)
          lor (if n > 1 then arg_type y lsl 4 else 0)
          lor (if n > 2 then arg_type z lsl 6 else 0)
      in
      let ver = select ctx proto (n + 1) tag in
      let b = ctx.b in
      let nb = b + off in
      let pk = ver.pk in
      put ctx pk nb 0 self;
      if n > 0 then put ctx pk nb 1 x;
      if n > 1 then put ctx pk nb 2 y;
      if n > 2 then put ctx pk nb 3 z;
      finish ctx proto ver env nb b s
    | _ -> others ctx g x y z
  in
  match n with
  | 0 ->
    fun ctx ->
      let g = callee ctx in
      ctx.site <- s;
      slow ctx g Undef Undef Undef
  | 1 ->
    fun ctx ->
      let g = callee ctx in
      let x = arg_value ctx sa a in
      ctx.site <- s;
      (match g with
       | Fun { proto; env } when proto.arity = 1 ->
         share_if (proto.func.kept land lent) 0 x;
         let tag = if no_spec then no_tag else arg_type x in
         let key = tag lor (1 lsl 42) in
         let ver =
           match proto.last with
           | Last l when l.ltag = key -> l.lver
           | _ -> select_slow ctx proto 1 tag key
         in
         let b = ctx.b in
         let nb = b + off in
         put ctx ver.pk nb 0 x;
         finish ctx proto ver env nb b s
       | _ -> slow ctx g x Undef Undef)
  | 2 ->
    fun ctx ->
      let g = callee ctx in
      let x = arg_value ctx sa a in
      let y = arg_value ctx sd d in
      ctx.site <- s;
      (match g with
       | Fun { proto; env } when proto.arity = 2 ->
         let kept = proto.func.kept land lent in
         share_if kept 0 x;
         share_if kept 1 y;
         let tag = if no_spec then no_tag else arg_type x lor (arg_type y lsl 2) in
         let key = tag lor (2 lsl 42) in
         let ver =
           match proto.last with
           | Last l when l.ltag = key -> l.lver
           | _ -> select_slow ctx proto 2 tag key
         in
         let b = ctx.b in
         let nb = b + off in
         let pk = ver.pk in
         put ctx pk nb 0 x;
         put ctx pk nb 1 y;
         finish ctx proto ver env nb b s
       | _ -> slow ctx g x y Undef)
  | _ ->
    fun ctx ->
      let g = callee ctx in
      let x = arg_value ctx sa a in
      let y = arg_value ctx sd d in
      let z = arg_value ctx sf f in
      ctx.site <- s;
      (match g with
       | Fun { proto; env } when proto.arity = 3 ->
         let tag =
           if no_spec then no_tag else arg_type x lor (arg_type y lsl 2) lor (arg_type z lsl 4)
         in
         let kept = proto.func.kept land lent in
         share_if kept 0 x;
         share_if kept 1 y;
         share_if kept 2 z;
         let ver = select ctx proto 3 tag in
         let b = ctx.b in
         let nb = b + off in
         let pk = ver.pk in
         put ctx pk nb 0 x;
         put ctx pk nb 1 y;
         put ctx pk nb 2 z;
         finish ctx proto ver env nb b s
       | _ -> slow ctx g x y z)

(* The arguments are boxed in v at b + off: read their real types. *)
and dispatch ctx g off n s =
  match g with
  | Fun { proto; env } ->
    let f = proto.func in
    let np = Array.length f.params in
    if n > np then Runtime.fail ctx Type (Messages.too_many f.fname np n);
    let b = ctx.b in
    let nb = b + off in
    let tag = if n > 20 then no_tag else arg_tag ctx nb n in
    let ver = select ctx proto n tag in
    let need = Int.max ver.size (ver.frame + 2) in
    if nb + need > ctx.cap then Runtime.grow ctx (nb + need);
    (* The parameters go to the stacks the version expects. *)
    let tv = ver.tv and map = ver.map in
    for i = 0 to n - 1 do
      let p = map.(i) in
      match tv.(i) with
      | TI -> ctx.i.(nb + p) <- to_i ctx ctx.v.(nb + i)
      | TF -> Float.Array.set ctx.f (nb + p) (to_f ctx ctx.v.(nb + i))
      | _ -> if p <> i then ctx.v.(nb + p) <- ctx.v.(nb + i)
    done;
    for i = n to np - 1 do
      if ver.sg.(i) != TBot then ctx.v.(nb + map.(i)) <- Undef
    done;
    enter ctx nb s ver;
    let caps = f.captures in
    for j = 0 to Array.length caps - 1 do
      ctx.v.(nb + map.(snd caps.(j))) <- env.(j)
    done;
    let r = ver.rv ctx in
    ctx.b <- b;
    r
  | Native nat ->
    if n < nat.min_args || n > nat.max_args then
      Runtime.fail ctx Type (Messages.arg_count nat.nname (string_of_int nat.min_args ^ " arguments") n);
    (match nat.perm with
     | Some p -> Runtime.check_perm ctx p None
     | None -> ());
    let vals = Array.sub ctx.v (ctx.b + off) n in
    nat.run ctx vals
  | Bound { g; self } ->
    with_object ctx off n g self;
    dispatch ctx g off (n + 1) s
  | _ -> Runtime.fail ctx Type (Messages.not_function (Value.describe g))

(* The object of a method goes under the arguments, boxed in v at b + off. *)
and with_object ctx off n g self =
  let nb = ctx.b + off in
  if nb + n + 3 > ctx.cap then Runtime.grow ctx (nb + n + 3);
  Array.blit ctx.v nb ctx.v (nb + 1) n;
  (match g with
   | Fun { proto; _ } -> share_if proto.func.kept 0 self
   | _ -> ());
  ctx.v.(nb) <- self

(* The version for these real types: the last one seen, else the function's table. *)
and select (ctx : ctx) (proto : proto) n tag =
  let key = tag lor (n lsl 42) in
  match proto.last with
  | Last l when l.ltag = key -> l.lver
  | _ -> select_slow ctx proto n tag key

and select_slow ctx proto n tag key =
  let v =
    match find_in key proto.by_tag with
    | Some v -> v
    | None -> pick ctx proto n tag
  in
  proto.last <- Last { ltag = key; lver = v };
  v

(* First time a function sees these types: pick or create the version. *)
and pick ctx (proto : proto) n tag =
  let f = proto.func in
  let np = Array.length f.params in
  for i = n to np - 1 do
    if f.params.(i).default = None then
      Runtime.fail ctx Type (Messages.missing_arg f.fname f.params.(i).pname)
  done;
  let v =
    if tag = no_tag then Infer.generic_version proto
    else Infer.version_for ctx.w proto (Array.init np (fun i -> if i < n then tag_type tag i else TBot))
  in
  Infer.run ctx.w v;
  (* Compiled right away: version.size is then valid on the fast path. *)
  if v.size = 0 then compile_version ctx v;
  proto.by_tag <- (tag lor (n lsl 42), v) :: proto.by_tag;
  v

and dispatch_named ctx g off names s =
  let b = ctx.b + off in
  let n = Array.length names in
  match g with
  | Fun { proto; _ } ->
    let f = proto.func in
    let np = Array.length f.params in
    let vals = Array.sub ctx.v b n in
    let out = Array.make (max np n) Undef in
    Array.iteri
      (fun i name ->
         match name with
         | None ->
           if i >= np then Runtime.fail ctx Type (Messages.too_many f.fname np n);
           out.(i) <- vals.(i)
         | Some name ->
           let found = ref (-1) in
           Array.iteri (fun k (p : param) -> if String.equal p.pname name then found := k) f.params;
           if !found < 0 then Runtime.fail ctx Type (Messages.unknown_arg f.fname name);
           if out.(!found) != Undef then Runtime.fail ctx Type (Messages.duplicate_arg f.fname name);
           out.(!found) <- vals.(i))
      names;
    let last = ref 0 in
    Array.iteri
      (fun k v ->
         if k < np then
           if v == Undef then begin
             if f.params.(k).default = None then
               Runtime.fail ctx Type (Messages.missing_arg f.fname f.params.(k).pname)
           end else last := k + 1)
      out;
    if b + np + 2 > ctx.cap then Runtime.grow ctx (b + np + 2);
    Array.blit out 0 ctx.v b np;
    dispatch ctx g off !last s
  | Native nat ->
    let vals = Array.sub ctx.v b n in
    let position i = function
      | None -> i
      | Some name ->
        (match Array.find_index (String.equal name) nat.params with
         | Some k -> k
         | None -> Runtime.fail ctx Type (Messages.unknown_arg nat.nname name))
    in
    let places = Array.mapi position names in
    let size = Array.fold_left (fun acc k -> max acc (k + 1)) 0 places in
    if b + size + 2 > ctx.cap then Runtime.grow ctx (b + size + 2);
    Array.fill ctx.v b size Undef;
    Array.iteri (fun i k -> ctx.v.(b + k) <- vals.(i)) places;
    dispatch ctx g off size s
  | Bound { g; self } ->
    with_object ctx off n g self;
    dispatch_named ctx g off (Array.append [| None |] names) s
  | _ -> dispatch ctx g off n s

and call_value (ctx : ctx) ~base g args =
  ctx.w.compile_ver <- compile_version;
  let n = Array.length args in
  if ctx.b + base + n + 2 > ctx.cap then Runtime.grow ctx (ctx.b + base + n + 2);
  Array.blit args 0 ctx.v (ctx.b + base) n;
  dispatch ctx g base n ctx.site

and call_back (ctx : ctx) g args =
  let base =
    match (Dynarray.get ctx.w.sites ctx.site).sver with
    | Some v -> v.size
    | None -> 0
  in
  call_value ctx ~base g args

(* User.From(m): an Ok of a User built from the keys of a map, or an Err that names the key: the data comes from outside, so a
   bad one is an error, not a bug. A small field is no key outside the package [pm] of the code, and its name is not told. *)
and from_native (proto : proto) pm =
  let ctor = Fun { proto; env = [||] } in
  let run (ctx : ctx) (a : t array) =
    let f = proto.func and sn = proto.pname in
    let names = Array.map (fun (p : param) -> p.pname) f.params in
    let shape = Value.shape_of ctx.w ~sname:sn ~m:ctx.w.modules.(proto.pm).host names in
    let inside = ctx.w.modules.(pm).host = shape.sm in
    let o = Dict.items ctx (sn ^ ".From") a.(0) and vals = Array.make (Array.length names) Undef in
    let fail (m : Messages.t) = raise_notrace (Return_value (Value.failure ctx.w "field" m.text)) in
    try
      for j = 0 to (Array.length o / 2) - 1 do
        let key = Value.text_of ctx o.(2 * j) in
        let i = (match o.(2 * j) with Text s when Lexer.is_public s || inside -> Value.field_index shape s | _ -> -1) in
        if i < 0 then fail (Messages.named_field sn key);
        vals.(i) <- (if Array.length shape.checks = 0 then o.((2 * j) + 1) else
          match shape.checks.(i) with
          | None -> o.((2 * j) + 1)
          | Some ch ->
            let y = ch.accept o.((2 * j) + 1) in
            if y == Undef then fail (Messages.wrong_type sn names.(i) (fst (ch.wrong o.((2 * j) + 1))) (snd (ch.wrong o.((2 * j) + 1))));
            y)
      done;
      Array.iteri
        (fun i (p : param) ->
           if vals.(i) == Undef && p.default = None then
             fail (if inside || Lexer.is_public p.pname then Messages.from_missing sn p.pname else Messages.from_private sn))
        f.params;
      let last = ref 0 in
      Array.iteri (fun i v -> if v != Undef then last := i + 1) vals;
      Value.ok ctx.w (call_back ctx ctor (Array.map Value.share (Array.sub vals 0 !last)))
    with Return_value e -> e
  in
  Native { nname = proto.pname ^ ".From"; perm = None; params = [| "m" |]; min_args = 1; max_args = 1; ret_ty = (fun _ -> TA);
           run; f1 = None; i2 = None }

let run_main (ctx : ctx) ~file ~m (fn : func) =
  let proto = new_proto ~file ~m fn in
  let w = ctx.w in
  w.compile_ver <- compile_version;
  let ver = Infer.version_for w proto [||] in
  let ver = if ver.sg = [||] && not w.no_spec then (let v = Infer.make_version proto [||] in proto.versions <- [ v ]; v) else ver in
  compile_version ctx ver;
  ignore (ver.rv ctx);
  (* Variables that stayed local are copied to their cells, for export. *)
  let md = w.modules.(m) in
  Array.iteri
    (fun i k ->
       if fn.cell_of.(i) < 0 then begin
         let p = ctx.b + ver.map.(i) in
         md.cells.(k) <-
           (match ver.tv.(i) with
            | TI -> Int ctx.i.(p)
            | TF -> Float (Float.Array.get ctx.f p)
            | _ -> Value.share ctx.v.(p))
       end)
    fn.export_of


(* A version from before a reload. Already compiled code, sometimes still running, calls it: it keeps its frame
   layout, rereads its arguments and goes back through the dynamic call, hence to the new code. *)
let retire (old : version) =
  if old.state = 2 then begin
    let g = Fun { proto = old.owner; env = [||] } in
    let np = Array.length old.sg and map = old.map and tv = old.tv in
    let forward (ctx : ctx) =
      let nb = ctx.b in
      let arg k =
        let p = nb + map.(k) in
        if old.sg.(k) == TBot then Undef
        else
          match tv.(k) with
          | TI -> Int ctx.i.(p)
          | TF -> Float (Float.Array.get ctx.f p)
          | _ -> Value.share ctx.v.(p)
      in
      let args = Array.init np arg in
      let n = ref np in
      while !n > 0 && args.(!n - 1) == Undef do decr n done;
      let off = Int.max old.size (old.frame + 2) in
      if nb + off + !n + 2 > ctx.cap then Runtime.grow ctx (nb + off + !n + 2);
      Array.blit args 0 ctx.v (nb + off) !n;
      dispatch ctx g off !n ctx.i.(nb + 1)
    in
    old.rv <- forward;
    old.ri <- (fun ctx -> to_i ctx (forward ctx));
    old.rf <- (fun ctx -> to_f ctx (forward ctx))
  end

(* Everything recompiles on the next call: the callers of a changed function depend on its types. *)
let retire_all (w : world) =
  let forget (proto : proto) =
    let old = proto.versions @ Option.to_list proto.generic in
    proto.versions <- [];
    proto.generic <- None;
    proto.by_tag <- [];
    proto.last <- No_call;
    List.iter retire old
  in
  Array.iter
    (fun md ->
       Array.iter
         (function
           | Fun { proto; env = [||] } -> forget proto
           | _ -> ())
         md.cells)
    w.modules

let replace (proto : proto) ~file (f : func) =
  proto.func <- f;
  proto.file <- file;
  proto.arity <- Array.length f.params
