(* Cesia compiled ahead of time to WebAssembly: a program and the packages it uses, loaded and resolved as the interpreter
   loads them but run by none, become one module. From the resolved tree and the types that Infer gives each version
   of a function, the versions the interpreter would make for the same arguments, the code is typed where the types
   are known (an Int an i64 with Cesia's checks of 63 bits, a Float an f64) and generic elsewhere (values of the runtime,
   Rt). There is no interpreter in the page: what this slice doesn't compile is an error at the build, at its place.

   Why not the JIT's IR: its regions bail to the interpreter at each failed guard, and its frames live in the
   interpreter's stacks; with no interpreter to go back to, the backend takes what Lower takes, the tree and the
   versions' types, and lowers each version whole. *)

open Types
open Ast
open Wasm
open Rt

exception Unsupported of string * Pos.t * string  (* file, position, what *)

type kind = I | F | V

let kind_of = function TI -> I | TF -> F | _ -> V
let vt_of : kind -> Wasm.vt = function I -> I64 | F -> F64 | V -> Rt.v

type st = {
  w : world;
  rt : Rt.t;
  sites : string Vec.t;
  site_ids : (string, int) Hashtbl.t;
  mutable vers : (version * string) list;
  mutable todo : version list;
  mutable lambdas : (Ast.func * proto) list;
  mutable counter : int;
  mutable values : (version * string) list;  (* the entry of a version called as a value *)
}

(* A function being compiled. *)
type fc = {
  st : st;
  fb : Rt.fb;
  ver : version;
  fn : Ast.func;
  path : string;
  pname : string;
  file : int;
  pm : int;
  locs : int array;  (* each variable's local, -1 for a cell *)
  kinds : kind array;
  env : int;  (* the local of the captured values, -1 when none *)
  mutable labels : string list;
  mutable ends : int list;  (* the locals of the arrays that an [end] measures, the innermost first *)
  hoisted : Ast.func list;
  tail : int;  (* the local of the self tail call's flag, -1 *)
  exit : (ins list * int) option;
      (* in a loop's chunk: the code that gives back its state, and the local of the function's result *)
  fixed : (int * int * int) list;
      (* in a loop's chunk, the float arrays it reads and never writes: variable, the local of its floats, of its count *)
}

(* A loop's chunk runs at most this many turns a call. *)
let chunk_size = 1 lsl 14

let unsupported fc (pos : Pos.t) what = raise (Unsupported (fc.path, pos, what))

(* The cell of a file's variable that stays out of the locals; in a loop's chunk, a variable it was not given is a bug of
   the compiler. *)
let cell_index fc i = if fc.locs.(i) = -3 then failwith "aot: a variable read in a loop it wasn't given" else fc.fn.cell_of.(i)

(* Sites: where an error can be, with what the loader writes of it. *)
let json_text s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
       match c with
       | '"' -> Buffer.add_string b "\\\""
       | '\\' -> Buffer.add_string b "\\\\"
       | '\n' -> Buffer.add_string b "\\n"
       | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
       | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let site_at st file pos fname =
  let path, src = Vec.get st.w.files file in
  let key = Printf.sprintf "%d:%d:%s" file pos fname in
  match Hashtbl.find_opt st.site_ids key with
  | Some i -> i
  | None ->
    let full = Loader.format_error ~source:(Some src) ~path ~pos ~text:"" ~hint:None ~trace:[] in
    let cut = String.index full '\n' in
    let header = String.sub full 0 cut and excerpt = String.sub full (cut + 1) (String.length full - cut - 1) in
    let place = if fname = "" then "" else Printf.sprintf "%s (%s:%d)" fname path (Pos.line pos) in
    let lib = String.starts_with ~prefix:"std/" path || String.starts_with ~prefix:"deps/" path in
    let i = Vec.length st.sites in
    Vec.add_last st.sites (Printf.sprintf "[%s,%s,%s,%d]" (json_text header) (json_text excerpt) (json_text place) (if lib then 1 else 0));
    Hashtbl.replace st.site_ids key i;
    i

let site fc pos = [ I32 (site_at fc.st fc.file pos fc.pname) ]

(* Labels of the structured blocks, for br. *)
let depth_of fc name =
  let rec go i = function
    | [] -> failwith ("no label " ^ name)
    | l :: rest -> if l = name then i else go (i + 1) rest
  in
  go 0 fc.labels

let nest fc name f =
  fc.labels <- name :: fc.labels;
  let r = f () in
  fc.labels <- List.tl fc.labels;
  r

let block fc name bt f = Block (bt, nest fc name f)
let loop fc name bt f = Loop (bt, nest fc name f)
let iff fc bt yes no = If (bt, nest fc "" yes, nest fc "" no)

(* Conversions between kinds. *)
let convert fc ~from ~into =
  let rt = fc.st.rt in
  match from, into with
  | I, I | F, F | V, V -> []
  | I, F -> [ f64_of_i64 ]
  | I, V -> [ call rt "box_i" ]
  | F, V -> [ call rt "box_f" ]
  | V, I -> [ call rt "int_of" ]
  | V, F -> [ call rt "as_float" ]
  | F, I -> [ i64_trunc_sat ]

let ty fc (e : expr) = fc.ver.tn.(e.id)
let kind fc e = kind_of (ty fc e)

(* The versions to compile: each one's function, made once. *)
let ver_name st (v : version) =
  match List.assq_opt v st.vers with
  | Some n -> n
  | None ->
    st.counter <- st.counter + 1;
    let n = Printf.sprintf "f%d:%s" st.counter v.owner.pname in
    st.vers <- (v, n) :: st.vers;
    st.todo <- v :: st.todo;
    n

let has_env (f : Ast.func) = Array.length f.captures > 0

let ready w (v : version) = if v.state <> 2 then Infer.run w v

(* The parameters and result of a version's function. *)
let signature st (v : version) =
  let f = Cache.ready v.owner.func in
  ready st.w v;
  let np = Array.length f.params in
  let ps = List.init np (fun k -> vt_of (kind_of v.tv.(k))) in
  ((if has_env f then [ Rt.nl st.rt.vals ] else []) @ ps), [ vt_of (kind_of v.ret) ]

let proto_of st ~file ~m (f : Ast.func) =
  match List.assq_opt f st.lambdas with
  | Some p -> p
  | None ->
    let p = Compile.new_proto ~file ~m f in
    st.lambdas <- (f, p) :: st.lambdas;
    p

(* The version a call through a value takes: all its parameters of any type. *)
let value_version st (p : proto) =
  let v = Infer.version_for st.w p (Array.make (Array.length p.func.params) TA) in
  ready st.w v;
  v

(* A version called as a value: its entry takes the function value, then its arguments, all values. *)
let value_entry st (v : version) =
  match List.assq_opt v st.values with
  | Some n -> n
  | None ->
    let rt = st.rt in
    let impl = ver_name st v in
    let f = Cache.ready v.owner.func in
    let np = Array.length f.params in
    let n = "val:" ^ impl in
    st.values <- (v, n) :: st.values;
    let ef = Wasm.func rt.m n (Rt.nn rt.fn :: List.init np (fun _ -> Rt.v)) [ Rt.v ] in
    ignore (Rt.fn_type rt np);
    let args = List.concat (List.init np (fun k -> [ Lget (k + 1) ] @ (match kind_of v.tv.(k) with V -> [] | I -> [ call rt "int_of" ] | F -> [ call rt "as_float" ]))) in
    ef.body <- (if has_env f then [ Lget 0; struct_get rt.fn f_env ] else []) @ args @ [ Call impl ]
               @ (match kind_of v.ret with V -> [] | I -> [ call rt "box_i" ] | F -> [ call rt "box_f" ]);
    n

let fn_global st (p : proto) =
  let rt = st.rt in
  let v = value_version st p in
  let entry = value_entry st v in
  let g = "fn:" ^ entry in
  if not (Wasm.has_global rt.m g) then begin
    let f = Cache.ready p.func in
    let np = Array.length f.params in
    let least = Array.fold_left (fun n (q : param) -> if q.default = None then n + 1 else n) 0 f.params in
    let name = text rt p.pname in
    Wasm.global rt.m g (Rt.nn rt.fn) false [ Rfunc entry; I32 np; I32 least; name; Rnull (T rt.vals); struct_new rt.fn ]
  end;
  Gget g

(* Module cells: a global each, unset at the start. *)
let cell_global st m k =
  let rt = st.rt in
  let g = Printf.sprintf "cell:%d:%d" m k in
  if not (Wasm.has_global rt.m g) then begin
    let undef = g_undef rt in
    Wasm.global rt.m g Rt.v true [ undef ]
  end;
  g

(* The natives this slice compiles, by package and name: their code from the arguments' code and kinds, and the kind of
   what they give. *)
type native_call = fc -> expr array -> pos -> kind -> ins list

let natives : (string * string, native_call) Hashtbl.t = Hashtbl.create 32

(* The variables of the function that this code reads or writes, into [seen], and whether it can leave the function
   (a return, a ?). A function defined in it has its own variables, but reads here those it captures. *)
let rec scan ?(written = Hashtbl.create 1) seen leaves (e : expr) =
  let go = scan ~written seen leaves in
  let name (n : name) = match n.b with Local i -> Hashtbl.replace seen i () | _ -> () in
  let set (n : name) = name n; match n.b with Local i -> Hashtbl.replace written i () | _ -> () in
  let func (f : Ast.func) = Array.iter (fun (outer, _) -> Hashtbl.replace seen outer ()) f.captures in
  let block b = Array.iter go b in
  let ixs = Array.iter (function All -> () | Ix e -> go e) in
  let rec pat = function
    | Pname n -> set n
    | Pwild -> ()
    | Plit e -> go e
    | Parray ps -> Array.iter pat ps
    | Pstruct fs -> Array.iter (fun (_, p) -> pat p) fs
    | Pcons c -> Array.iter pat c.cargs
  in
  match e.e with
  | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ | Break | End_index | Use _ | Interface _ | Hook _ -> ()
  | Interp parts -> Array.iter (function Lit _ -> () | Hole e -> go e) parts
  | Var n -> name n
  | Bin (_, a, b) | And (a, b) | Or (a, b) | Range (a, b) | In_op (a, b) -> go a; go b
  | Neg a | Not a | Field (a, _) -> go a
  | Question a -> leaves := true; go a
  | Bang a -> go a
  | Call c -> go c.callee; Array.iter (fun (a : arg) -> go a.value) c.args
  | Assign (n, v) -> set n; go v
  | If (c, y, n) -> go c; block y; block n
  | While { cond; body; _ } -> go cond; block body
  | Return r -> leaves := true; Option.iter go r.rvalue
  | Lambda f -> func f
  | Fn_def (n, f) -> set n; func f
  | Array_lit rows -> Array.iter (Array.iter go) rows
  | Comp { cbody; cvar; csrc; cguard } -> go cbody; set cvar; go csrc; Option.iter go cguard
  | Index (b, is, _) -> go b; ixs is
  | Struct_lit { sfields; _ } -> Array.iter (fun (_, v) -> go v) sfields
  | For { var; iter; fbody; _ } -> set var; go iter; block fbody
  | Set { root; path; value } ->
    set root;
    Array.iter (fun (st : step) -> match st.sk with Sindex (is, _) -> ixs is | Sfield _ -> ()) path;
    go value
  | Destructure (p, v) -> pat p; go v
  | Match { subject; arms } -> go subject; Array.iter (fun a -> pat a.pt; Option.iter go a.guard; go a.abody) arms

let zero = function I -> [ I64 0L ] | F -> [ F64 0. ] | V -> [ Rt.missing ]

let rec expr fc (e : expr) (want : kind) : ins list =
  let k, code = natural fc e in
  code @ convert fc ~from:k ~into:want

(* A value about to be stored elsewhere: a second reference leads to it, unless it is new ([Compile.ce]). *)
and stored fc (e : expr) : ins list =
  match e.e with
  | Var _ | Index _ | Field _ ->
    (match kind fc e with V -> expr fc e V @ [ call fc.st.rt "share" ] | k -> expr fc e k @ convert fc ~from:k ~into:V)
  | If (c, y, n) -> cond fc c @ [ iff fc (Bval Rt.v) (fun () -> block_stored fc y) (fun () -> block_stored fc n) ]
  | _ -> expr fc e V

and block_stored fc (b : block) =
  let n = Array.length b in
  if n = 0 then [ missing ]
  else List.concat (List.init (n - 1) (fun i -> stmt fc b.(i))) @ stored fc b.(n - 1)

(* An expression in its own kind. *)
and natural fc (e : expr) : kind * ins list =
  let rt = fc.st.rt in
  let k = kind fc e in
  match e.e with
  | Lint i -> if k = F then F, [ F64 (float_of_int i) ] else I, [ I64 (Int64.of_int i) ]
  | Lfloat x -> F, [ F64 x ]
  | Lbool b -> V, [ if b then g_true rt else g_false rt ]
  | Lmissing -> V, [ missing ]
  | Ltext s -> V, [ text rt s ]
  | Interp parts -> V, interp fc parts
  | Var n -> var fc e n
  | Bin (op, a, b) -> binary fc e op a b
  | Neg a ->
    (match k with
     | I -> I, expr fc a I @ site fc e.pos @ [ call rt "neg_i" ]
     | F -> F, expr fc a F @ [ f64_neg ]
     | V -> V, expr fc a V @ site fc e.pos @ [ call rt "neg" ])
  | Not _ | And _ | Or _ -> V, cond fc e @ bool_of rt
  | If (c, y, n) -> k, cond fc c @ [ iff fc (Bval (vt_of k)) (fun () -> block_value fc y k) (fun () -> block_value fc n k) ]
  | Call call -> call_expr fc e call
  | Lambda f -> V, closure fc f
  | Range (a, b) -> V, bound fc a e.pos @ bound fc b e.pos @ site fc e.pos @ [ call rt "range" ]
  | In_op _ -> unsupported fc e.pos "in"
  | Array_lit rows -> V, array_lit fc e rows
  | Comp { cbody; cvar; csrc; cguard } -> V, comprehension fc e cbody cvar csrc cguard
  | Index (b, ixs, uses_end) -> index_read fc e b ixs uses_end
  | Field (b, name) -> V, expr fc b V @ [ text rt name; cache rt ] @ site fc e.pos @ [ call rt "field" ]
  | Struct_lit { sname; sfields } -> V, struct_lit fc e sname sfields
  | End_index ->
    (match fc.ends with
     | l :: _ -> I, [ Lget l; Cast (false, T rt.list); call rt "cells"; i64_extend_u ]
     | [] -> unsupported fc e.pos "end")
  | Question a -> V, question fc e a false
  | Bang a -> V, question fc e a true
  | Match { subject; arms } -> k, match_expr fc e subject arms k
  | Return r -> V, return fc e r
  | Assign _ | While _ | For _ | Set _ | Break | Fn_def _ | Destructure _ | Use _ | Interface _ | Hook _ ->
    V, stmt fc e @ [ missing ]

and block_value fc (b : block) k =
  let n = Array.length b in
  if n = 0 then [ missing ] @ convert fc ~from:V ~into:k
  else List.concat (List.init (n - 1) (fun i -> stmt fc b.(i))) @ expr fc b.(n - 1) k

(* A statement: its code leaves nothing. *)
and stmt fc (e : expr) : ins list =
  let rt = fc.st.rt in
  match e.e with
  | Use _ | Interface _ -> []
  | Fn_def ({ b = Cell _; _ }, _) -> []
  | Fn_def ({ b = Local i; _ } as n, f) ->
    if List.memq f fc.hoisted then []
    else begin
      (* A function that calls itself holds itself in its captured values. *)
      let self = List.filter_map (fun (j, (outer, _)) -> if outer = i then Some j else None) (List.mapi (fun j p -> j, p) (Array.to_list f.captures)) in
      let g = Rt.local fc.fb Rt.v in
      closure fc f @ [ Lset g ]
      @ List.concat_map (fun j -> [ Lget g; Cast (false, T rt.fn); struct_get rt.fn f_env; as_non_null; I32 j; Lget g; array_set rt.vals ]) self
      @ write_var fc n e.pos [ Lget g ] V
    end
  | Fn_def (_, _) -> unsupported fc e.pos "this definition"
  | Assign (n, v) ->
    let k = match n.b with Local i when fc.locs.(i) >= 0 -> fc.kinds.(i) | _ -> V in
    let value = if k = V then stored fc v else expr fc v k in
    write_var fc n e.pos value k
  | If (c, y, n) -> cond fc c @ [ iff fc Bnone (fun () -> block_stmts fc y) (fun () -> block_stmts fc n) ]
  | While { cond = c; body; _ } ->
    let looped cf _ next =
      [ block cf "break" Bnone (fun () ->
            [ loop cf "loop" Bnone (fun () ->
                  cond cf c @ [ i32_eqz; Br_if (depth_of cf "break") ] @ block_stmts cf body @ next ()
                  @ [ Br (depth_of cf "loop") ]) ]) ]
    in
    if fc.ends = [] then outlined fc (c :: Array.to_list body) [] [] (fun _ -> []) looped else looped fc [] (fun () -> tick rt)
  | For { var; iter; fbody; _ } -> for_loop fc ~outline:(fc.ends = []) ~scanned:(Array.to_list fbody) var iter (fun cf -> block_stmts cf fbody)
  | Break -> [ Br (depth_of fc "break") ]
  | Set { root; path; value } -> set_path fc e root path value
  | Destructure (pt, v) -> destructure fc e pt v
  | Return r -> return fc e r
  | Hook _ -> []
  | _ ->
    let k, code = natural fc e in
    ignore k;
    code @ [ drop ]

and block_stmts fc b = List.concat_map (stmt fc) (Array.to_list b)

(* A condition, as an i32. *)
and cond fc (e : expr) : ins list =
  let rt = fc.st.rt in
  match e.e with
  | Lbool b -> [ I32 (if b then 1 else 0) ]
  | Not a -> cond fc a @ [ i32_eqz ]
  | And (a, b) -> cond fc a @ [ iff fc (Bval I32) (fun () -> cond fc b) (fun () -> [ I32 0 ]) ]
  | Or (a, b) -> cond fc a @ [ iff fc (Bval I32) (fun () -> [ I32 1 ]) (fun () -> cond fc b) ]
  | Bin (((Lt | Le | Gt | Ge | Eq | Ne) as op), a, b) when typed fc a && typed fc b -> compare_typed fc op a b
  | _ -> expr fc e V @ site fc e.pos @ [ call rt "truth" ]

and typed fc e = match kind fc e with I | F -> true | V -> false

(* A comparison of two numbers whose kinds are known: an integer against a float exactly, as Trie.int_float. *)
and compare_typed fc op a b =
  let rt = fc.st.rt in
  let ka = kind fc a and kb = kind fc b in
  let i_op = function Lt -> i64_lt_s | Le -> i64_le_s | Gt -> i64_gt_s | Ge -> i64_ge_s | Eq -> i64_eq | _ -> i64_ne in
  let f_op = function Lt -> f64_lt | Le -> f64_le | Gt -> f64_gt | Ge -> f64_ge | Eq -> f64_eq | _ -> f64_ne in
  match ka, kb with
  | I, I -> expr fc a I @ expr fc b I @ [ i_op op ]
  | F, F -> expr fc a F @ expr fc b F @ [ f_op op ]
  | _ ->
    (* c = int_float(i, f): -1, 0, 1, or 2 for NaN. *)
    let c = Rt.local fc.fb I32 in
    let flip = ka = F in
    let code = if flip then expr fc b I @ expr fc a F else expr fc a I @ expr fc b F in
    let op = if flip then (match op with Lt -> Gt | Le -> Ge | Gt -> Lt | Ge -> Le | o -> o) else op in
    code @ [ call rt "int_float"; Lset c ]
    @ (match op with
        | Eq -> [ Lget c; i32_eqz ]
        | Ne -> [ Lget c; I32 0; i32_ne ]
        | Lt -> [ Lget c; I32 (-1); i32_eq ]
        | Gt -> [ Lget c; I32 1; i32_eq ]
        | Le -> [ Lget c; I32 0; i32_le_s ]
        | _ -> [ Lget c; I32 0; i32_ge_s; Lget c; I32 2; i32_ne; i32_and ])

and binary fc e op a b =
  let rt = fc.st.rt in
  let k = kind fc e in
  let arith_op = function Add -> 0 | Sub -> 1 | Mul -> 2 | Div -> 3 | _ -> 4 in
  match op with
  | Add | Sub | Mul ->
    (match k with
     | I -> I, Rt.checked rt fc.fb (match op with Add -> `Add | Sub -> `Sub | _ -> `Mul) (expr fc a I) (expr fc b I) (site fc e.pos)
     | F -> F, expr fc a F @ expr fc b F @ [ (match op with Add -> f64_add | Sub -> f64_sub | _ -> f64_mul) ]
     | V -> V, [ I32 (arith_op op) ] @ expr fc a V @ expr fc b V @ site fc e.pos @ [ call rt "arith" ])
  | Div ->
    (match k with
     | F -> F, expr fc a F @ expr fc b F @ [ f64_div ]
     | _ -> V, [ I32 3 ] @ expr fc a V @ expr fc b V @ site fc e.pos @ [ call rt "arith" ] @ convert fc ~from:V ~into:V)
  | Pow ->
    (match k with
     | I -> I, expr fc a I @ expr fc b I @ site fc e.pos @ [ call rt "pow_i" ]
     | F -> F, expr fc a F @ expr fc b F @ [ host rt "pow" ]
     | V -> V, [ I32 4 ] @ expr fc a V @ expr fc b V @ site fc e.pos @ [ call rt "arith" ])
  | Lt | Le | Gt | Ge ->
    if typed fc a && typed fc b then V, cond fc e @ bool_of rt
    else V, [ I32 (match op with Lt -> 0 | Le -> 1 | Gt -> 2 | _ -> 3) ] @ expr fc a V @ expr fc b V @ site fc e.pos @ [ call rt "cmp" ]
  | Eq | Ne ->
    if typed fc a && typed fc b then V, cond fc e @ bool_of rt
    else V, [ I32 (if op = Eq then 0 else 1) ] @ expr fc a V @ expr fc b V @ [ call rt "eqv" ]

and interp fc parts =
  let rt = fc.st.rt in
  let b = Rt.local fc.fb (Rt.nn rt.buf) in
  [ call rt "buf_new"; Lset b ]
  @ List.concat_map
    (function
      | Lit s -> [ Lget b; text rt s; call rt "buf_add" ]
      | Hole e -> [ Lget b ] @ expr fc e V @ [ call rt "text_of"; call rt "buf_add" ])
    (Array.to_list parts)
  @ [ Lget b; call rt "buf_done" ]

and var fc e (n : name) : kind * ins list =
  let rt = fc.st.rt in
  let unset_check get =
    let x = Rt.local fc.fb Rt.v in
    get @ [ Ltee x; g_undef rt; ref_eq; If (Bnone, Rt.fail rt (Messages.unset n.text) [] (site fc e.pos), []); Lget x ]
  in
  match n.b with
  | Local i when fc.locs.(i) >= 0 ->
    let get = [ Lget fc.locs.(i) ] in
    if fc.kinds.(i) = V && fc.fn.maybe_undef.(i) then V, unset_check get else fc.kinds.(i), get
  | Local i -> V, unset_check [ Gget (cell_global fc.st fc.pm (cell_index fc i)) ]
  | Cell { m; k; stable = true } ->
    (match fc.st.w.modules.(m).cells.(k) with
     | Fun { proto; env = [||] } -> V, [ fn_global fc.st proto ]
     | Float x when fc.st.w.modules.(m).path = "" -> F, [ F64 x ]
     | Int i when fc.st.w.modules.(m).path = "" -> I, [ i64 i ]
     | Text s when fc.st.w.modules.(m).path = "" -> V, [ text rt s ]
     | (True | False) as b when fc.st.w.modules.(m).path = "" -> V, [ if b = True then g_true rt else g_false rt ]
     | Missing when fc.st.w.modules.(m).path = "" -> V, [ missing ]
     | Native nat -> unsupported fc e.pos ("the native " ^ nat.nname ^ " as a value")
     | _ -> V, unset_check [ Gget (cell_global fc.st m k) ])
  | Cell { m; k; _ } -> V, unset_check [ Gget (cell_global fc.st m k) ]
  | Unresolved -> unsupported fc e.pos "an unresolved name"

(* Writes a variable from the code of a value of kind [k]. *)
and write_var fc (n : name) pos value k =
  match n.b with
  | Local i when fc.locs.(i) >= 0 -> value @ convert fc ~from:k ~into:fc.kinds.(i) @ [ Lset fc.locs.(i) ]
  | Local i -> value @ convert fc ~from:k ~into:V @ [ Gset (cell_global fc.st fc.pm (cell_index fc i)) ]
  | Cell { m; k = c; _ } -> value @ convert fc ~from:k ~into:V @ [ Gset (cell_global fc.st m c) ]
  | Unresolved -> unsupported fc pos "an unresolved name"

(* A bound of a..b, as an i64: a float of a whole value is accepted. *)
and bound fc (e : expr) pos =
  match kind fc e with
  | I -> expr fc e I
  | _ -> expr fc e V @ site fc pos @ [ call fc.st.rt "range_bound" ]

and array_lit fc e rows =
  let rt = fc.st.rt in
  let r = Array.length rows in
  let cols = if r = 0 then 0 else Array.length rows.(0) in
  if Array.exists (fun row -> Array.length row <> cols) rows then
    Rt.fail rt Messages.rows_differ [] (site fc e.pos)
  else begin
    (* Column by column, as the interpreter stores them. *)
    let cells = List.concat (List.init cols (fun j -> List.concat (List.init r (fun i -> stored fc rows.(i).(j))))) in
    [ I32 r; I32 cols ] @ cells @ [ array_new_fixed rt.vals (r * cols); call rt "list_of" ]
  end

(* for var in iter: a range counts in an i64 of its own, as the interpreter's for; an array is read cell by cell, its
   count taken at the start. *)
and for_loop fc ~outline ?(scanned = []) (var : name) (iter : expr) body =
  let rt = fc.st.rt in
  let vk = match var.b with Local i when fc.locs.(i) >= 0 -> fc.kinds.(i) | _ -> V in
  let var_ix = match var.b with Local i -> [ i ] | _ -> [] in
  let run state init looped =
    if outline then outlined fc scanned var_ix state init looped
    else
      let ls = List.map (fun t -> Rt.local fc.fb t) state in
      init ls @ looped fc ls (fun () -> tick rt)
  in
  match iter.e with
  | Range (a, b) ->
    run [ I64; I64 ]
      (function [ i; hi ] -> bound fc a iter.pos @ [ Lset i ] @ bound fc b iter.pos @ [ Lset hi ] | _ -> assert false)
      (fun cf ls next ->
         match ls with
         | [ i; hi ] ->
           [ block cf "break" Bnone (fun () ->
                 [ loop cf "loop" Bnone (fun () ->
                       [ Lget i; Lget hi; i64_gt_s; Br_if (depth_of cf "break") ]
                       @ write_var cf var iter.pos [ Lget i ] I
                       @ [ block cf "continue" Bnone (fun () -> body cf) ]
                       @ [ Lget i; i64 1; i64_add; Lset i ] @ next () @ [ Br (depth_of cf "loop") ]) ]) ]
         | _ -> assert false)
  | _ ->
    run [ Rt.nl rt.list; I32; I32 ]
      (function
        | [ l; k; n ] ->
          let src = Rt.local fc.fb Rt.v in
          expr fc iter V @ [ Lset src;
                             Lget src; Test (false, T rt.list);
                             If (Bnone, [], Rt.fail rt (Messages.cant_loop a1) [ [ Lget src; call rt "describe" ] ] (site fc iter.pos));
                             Lget src; Cast (false, T rt.list); Lset l;
                             Lget l; I32 0; struct_set rt.list l_owned;
                             Lget l; as_non_null; call rt "cells"; Lset n; I32 0; Lset k ]
        | _ -> assert false)
      (fun cf ls next ->
         match ls with
         | [ l; k; n ] ->
           let elem =
             if vk = F then [ Lget l; struct_get rt.list l_store; Cast (false, T rt.f64s); Lget k; array_get rt.f64s ]
             else [ Lget l; as_non_null; Lget k; call rt "elem"; call rt "share" ]
           in
           [ block cf "break" Bnone (fun () ->
                 [ loop cf "loop" Bnone (fun () ->
                       [ Lget k; Lget n; i32_ge_u; Br_if (depth_of cf "break") ]
                       @ write_var cf var iter.pos elem (if vk = F then F else V)
                       @ [ block cf "continue" Bnone (fun () -> body cf) ]
                       @ [ Lget k; I32 1; i32_add; Lset k ] @ next () @ [ Br (depth_of cf "loop") ]) ]) ]
         | _ -> assert false)

(* A loop in a function of its own, its chunk, which runs at most [chunk_size] turns a call and is called again while
   the loop goes on. The engines run a function first with code made fast (V8's Liftoff, SpiderMonkey's baseline), then,
   once it has run a while, with optimized code (TurboFan, Ion), but only from its next call: a loop that runs long in
   the function that holds it would never leave the first code. The chunk gets the variables that the loop reads or
   writes and its own state (a range's counter and end, an array's cells and place), and gives them back, then a status:
   0 the loop is over, 1 its turns are spent, 2 the function returns, its result after the variables. *)
and outlined fc (scanned : expr list) (extra : int list) (state : Wasm.vt list) init looped =
  let st = fc.st and rt = fc.st.rt in
  let seen = Hashtbl.create 16 and leaves = ref false and written = Hashtbl.create 16 in
  List.iter (scan ~written seen leaves) scanned;
  List.iter (fun i -> Hashtbl.replace written i ()) extra;
  List.iter (fun i -> Hashtbl.replace seen i ()) extra;
  let live = List.sort compare (Hashtbl.fold (fun i () acc -> if fc.locs.(i) >= 0 then i :: acc else acc) seen []) in
  let rk = kind_of fc.ver.ret in
  let ps = state @ List.map (fun i -> vt_of fc.kinds.(i)) live in
  let rs = ps @ (if !leaves then [ vt_of rk ] else []) @ [ I32 ] in
  st.counter <- st.counter + 1;
  let wf = Wasm.func rt.m (Printf.sprintf "loop%d:%s" st.counter fc.pname) ps rs in
  let fb = { Rt.f = wf; n = 0; rev = []; tmp = -1 } in
  let ns = List.length state in
  let locs = Array.map (fun l -> if l = -1 then -1 else -3) fc.locs in
  List.iteri (fun j i -> locs.(i) <- ns + j) live;
  let push = List.init (List.length ps) (fun j -> Lget j) in
  let rv = if !leaves then Rt.local fb (vt_of rk) else -1 in
  (* The float arrays read and never written: their floats and count once, at the start. *)
  let fixed =
    List.filter_map
      (fun i ->
         if fc.ver.tv.(i) == TFA && not (Hashtbl.mem written i) && not fc.fn.maybe_undef.(i) then
           Some (i, Rt.local fb (Rt.nl rt.f64s), Rt.local fb I32)
         else None)
      live
  in
  let cf = { fc with fb; locs; labels = []; ends = []; tail = -1; exit = Some (push, rv); fixed } in
  let turns = Rt.local fb I32 in
  (* The fuel of the turns taken, at once. *)
  let spend =
    [ Gget (fuel rt); i64 chunk_size; Lget turns; i64_extend_u; i64_sub; i64_sub; Gset (fuel rt);
      Gget (fuel rt); i64 0; i64_le_s; If (Bnone, [ call rt "refuel" ], []) ]
  in
  let out status = spend @ push @ (if !leaves then zero rk else []) @ [ I32 status; ret ] in
  let la = Rt.local fb (Rt.nl rt.list) in
  let hoist =
    List.concat_map
      (fun (i, fs, n) ->
         [ Lget locs.(i); Test (false, T rt.list);
           If (Bnone, [ Lget locs.(i); Cast (false, T rt.list); Lset la; Lget la; struct_get rt.list l_store; Test (false, T rt.f64s);
                        If (Bnone, [ Lget la; struct_get rt.list l_store; Cast (false, T rt.f64s); Lset fs; Lget la; as_non_null; call rt "cells"; Lset n ], []) ], []) ])
      fixed
  in
  wf.body <-
    hoist @ [ I32 chunk_size; Lset turns;
      block cf "spent" Bnone (fun () ->
          looped cf (List.init ns Fun.id) (fun () -> [ Lget turns; I32 1; i32_sub; Ltee turns; i32_eqz; Br_if (depth_of cf "spent") ])
          @ out 0) ]
    @ out 1;
  wf.locals <- List.rev fb.rev;
  (* The caller: the state made, then the chunk called while its turns are spent. *)
  let temps = List.map (fun t -> Rt.local fc.fb t) state in
  let status = Rt.local fc.fb I32 in
  let back = if !leaves then Rt.local fc.fb (vt_of rk) else -1 in
  let gets = List.map (fun t -> Lget t) temps @ List.map (fun i -> Lget fc.locs.(i)) live in
  let sets = List.rev_map (fun l -> Lset l) (temps @ List.map (fun i -> fc.locs.(i)) live) in
  init temps
  @ [ block fc "done" Bnone (fun () ->
        [ loop fc "again" Bnone (fun () ->
              gets @ [ Call wf.fname; Lset status ] @ (if !leaves then [ Lset back ] else []) @ sets
              @ [ Lget status; I32 1; i32_eq; Br_if (depth_of fc "again") ]
              @ (if !leaves then [ Lget status; I32 2; i32_eq; iff fc Bnone (fun () -> leave_with fc [ Lget back ]) (fun () -> []) ] else [])) ]) ]

(* Leaves the function with the result that [value] gives, of its kind: from a loop's chunk, through the chunk's
   caller. *)
and leave_with fc value =
  match fc.exit with
  | None -> value @ leave fc @ [ ret ]
  | Some (_, -1) -> failwith "aot: a loop that returns, seen as one that doesn't"
  | Some (push, rv) -> value @ [ Lset rv ] @ push @ [ Lget rv; I32 2; ret ]

and comprehension fc e cbody cvar csrc cguard =
  let rt = fc.st.rt in
  ignore e;
  let out = Rt.local fc.fb (Rt.nn rt.list) in
  [ call rt "builder"; Lset out ]
  @ for_loop fc ~outline:false cvar csrc (fun fc ->
      let push = [ Lget out ] @ stored fc cbody @ [ call rt "push" ] in
      match cguard with
      | None -> push
      | Some g -> cond fc g @ [ iff fc Bnone (fun () -> push) (fun () -> []) ])
  @ [ Lget out; call rt "built" ]

and index_read fc e b ixs uses_end =
  let rt = fc.st.rt in
  match ixs with
  | [| Ix i |] ->
    let base = Rt.local fc.fb Rt.v in
    let with_end f = if uses_end then (fc.ends <- base :: fc.ends; let r = f () in fc.ends <- List.tl fc.ends; r) else f () in
    (match i.e with
     | Range _ -> unsupported fc e.pos "a slice"
     | _ -> ());
    let idx = with_end (fun () -> match kind fc i with I -> expr fc i I | _ -> expr fc i V) in
    let fixed = match b.e with Var { b = Local v; _ } -> List.find_opt (fun (w, _, _) -> w = v) fc.fixed | _ -> None in
    if kind fc i <> I then V, expr fc b V @ [ Lset base; Lget base ] @ idx @ site fc e.pos @ [ call rt "index_v" ]
    else if kind fc e = F && fixed <> None then begin
      (* A float array that the loop never writes: its floats and count taken at the chunk's start. *)
      let _, fs, n = Option.get fixed in
      let x = Rt.local fc.fb I64 in
      F, idx @ [ Lset x; Lget x; i64 1; i64_sub; Lget n; i64_extend_u; i64_ge_u;
                 If (Bnone, expr fc b V @ [ Lget x ] @ site fc e.pos @ [ call rt "index"; drop; unreachable ], []);
                 Lget fs; Lget x; i32_wrap; I32 1; i32_sub; array_get rt.f64s ]
    end
    else if ty fc b == TFA && kind fc e = F then
      (* A float array: its cell, checked. *)
      let x = Rt.local fc.fb I64 and l = Rt.local fc.fb (Rt.nl rt.list) in
      F, expr fc b V @ [ Lset base ] @ idx @ [ Lset x; Lget base; Cast (false, T rt.list); Lset l;
                                               Lget x; i64 1; i64_sub; Lget l; as_non_null; call rt "cells"; i64_extend_u; i64_ge_u;
                                               If (Bnone, [ Lget base; Lget x ] @ site fc e.pos @ [ call rt "index"; drop ], []);
                                               Lget l; struct_get rt.list l_store; Cast (false, T rt.f64s); Lget x; i32_wrap; I32 1; i32_sub; array_get rt.f64s ]
    else V, expr fc b V @ [ Lset base; Lget base ] @ idx @ site fc e.pos @ [ call rt "index" ]
  | _ -> unsupported fc e.pos "an index of several dimensions"

and struct_lit fc e sname fields =
  let rt = fc.st.rt in
  let names = Array.map fst fields in
  let n = Array.length names in
  if List.length (List.sort_uniq String.compare (Array.to_list names)) < n then unsupported fc e.pos "a map with a key twice";
  let vals = List.concat_map (fun (_, v) -> stored fc v) (Array.to_list fields) @ [ array_new_fixed rt.vals n ] in
  match sname with
  | None -> [ I32 1; keys rt names ] @ vals @ [ I32 n; I32 0; struct_new rt.map ]
  | Some s -> [ I32 1; shape rt s names ] @ vals @ [ struct_new rt.recd ]

(* e?: the value of an Ok, or the function returns the Err. e! (bang): the same Ok, and an Err stops the program at the !,
   as result.Unwrap does; any other value gets the type error of its sign. *)
and question fc e a bang =
  let rt = fc.st.rt in
  let x = Rt.local fc.fb Rt.v in
  let is name = [ Lget x; Test (false, T rt.recd);
                  If (Bval I32, [ Lget x; Cast (false, T rt.recd); struct_get rt.recd r_shape; struct_get rt.shape 0; text rt name; call rt "bytes_eq" ], [ I32 0 ]) ] in
  let ret_kind = kind_of fc.ver.ret in
  let err = if bang then bang_failed fc e x else leave_with fc ([ Lget x ] @ convert fc ~from:V ~into:ret_kind) in
  stored fc a @ [ Lset x ]
  @ is "Ok" @ [ If (Bnone, [], is "Err" @ [ If (Bnone, err, Rt.fail rt (Messages.sign_value (if bang then "!" else "?") a1)
                                                            [ [ Lget x; call rt "describe" ] ] (site fc e.pos)) ]) ]
  @ [ Lget x; Cast (false, T rt.recd); struct_get rt.recd r_fields; I32 0; array_get rt.vals; call rt "share" ]

(* What e! stops with at the Err x: the Message of its error, a map's or a record's, or else the error, as a text, as
   result.Unwrap gives it. *)
and bang_failed fc e x =
  let rt = fc.st.rt in
  let m = Rt.local fc.fb Rt.v and k = Rt.local fc.fb I32 in
  let message ty find vals =
    [ Lget m; Cast (false, T ty) ] @ find @ [ Lset k; Lget k; I32 0; i32_ge_s;
      If (Bnone, [ Lget m; Cast (false, T ty) ] @ vals @ [ Lget k; array_get rt.vals; Lset m ], []) ] in
  [ Lget x; Cast (false, T rt.recd); struct_get rt.recd r_fields; I32 0; array_get rt.vals; Lset m;
    Lget m; Test (false, T rt.map);
    If (Bnone, message rt.map [ text rt "Message"; call rt "map_find" ] [ struct_get rt.map m_vals ],
        [ Lget m; Test (false, T rt.recd);
          If (Bnone, message rt.recd [ struct_get rt.recd r_shape; struct_get rt.shape 1; text rt "Message"; call rt "find_name" ] [ struct_get rt.recd r_fields ], []) ]) ]
  @ Rt.fail rt (Messages.bang_err a1) [ [ Lget m; call rt "text_of" ] ] (site fc e.pos)

(* The way out of a function: its depth back. *)
and leave fc = if fc.pname = "" && fc.fn.cell_of <> [||] then [] else [ Gget (depth fc.st.rt); I32 1; i32_sub; Gset (depth fc.st.rt) ]

and return fc e (r : ret) =
  let k = kind_of fc.ver.ret in
  let value = match r.rvalue with Some v -> if k = V then stored fc v else expr fc v k | None -> [ missing ] @ convert fc ~from:V ~into:k in
  ignore e;
  leave_with fc value

and closure fc (f : Ast.func) =
  let rt = fc.st.rt in
  let p = proto_of fc.st ~file:fc.file ~m:fc.pm f in
  if not (has_env f) then [ fn_global fc.st p ]
  else begin
    let v = value_version fc.st p in
    let entry = value_entry fc.st v in
    let np = Array.length f.params in
    let least = Array.fold_left (fun n (q : param) -> if q.default = None then n + 1 else n) 0 f.params in
    let caps =
      List.concat_map
        (fun (outer, _) ->
           let k, get = var_value fc outer in
           get @ convert fc ~from:k ~into:V @ (if k = V then [ call rt "share" ] else []))
        (Array.to_list f.captures)
    in
    [ Rfunc entry; I32 np; I32 least; text rt p.pname ] @ caps @ [ array_new_fixed rt.vals (Array.length f.captures); struct_new rt.fn ]
  end

(* The value of a variable of this function, by its number. *)
and var_value fc i =
  if fc.locs.(i) >= 0 then fc.kinds.(i), [ Lget fc.locs.(i) ]
  else V, [ Gget (cell_global fc.st fc.pm (cell_index fc i)) ]

and match_expr fc e subject arms k =
  let rt = fc.st.rt in
  let x = Rt.local fc.fb Rt.v in
  let n = Array.length arms in
  stored fc subject @ [ Lset x ]
  @ [ block fc "match" (Bval (vt_of k)) (fun () ->
        List.concat
          (List.init n (fun j ->
               let a = arms.(j) in
               [ block fc "arm" Bnone (fun () ->
                     pat_test fc a.pt x (depth_of fc "arm")
                     @ (match a.guard with Some g -> cond fc g @ [ i32_eqz; Br_if (depth_of fc "arm") ] | None -> [])
                     @ expr fc a.abody k @ [ Br (depth_of fc "match") ]) ]))
        @ Rt.fail rt (Messages.no_match a1) [ [ Lget x; call rt "describe" ] ] (site fc e.pos)) ]

(* The test of a pattern against the value in local [x]: binds its names, and goes to [fail] when it doesn't accept it. *)
and pat_test fc (pt : pat) x fail =
  let rt = fc.st.rt in
  let deeper code = List.map (function Br_if d -> Br_if d | i -> i) code in
  ignore deeper;
  match pt with
  | Pwild -> []
  | Pname n -> write_var fc n 0 [ Lget x; call rt "share" ] V
  | Plit lit -> [ Lget x ] @ expr fc lit V @ [ call rt "equal"; i32_eqz; Br_if fail ]
  | Parray ps ->
    let l = Rt.local fc.fb (Rt.nl rt.list) in
    let want = Array.length ps in
    [ Lget x; Test (false, T rt.list); i32_eqz; Br_if fail;
      Lget x; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; I32 want; i32_ne; Br_if fail ]
    @ List.concat
      (List.init want (fun k ->
           let y = Rt.local fc.fb Rt.v in
           [ Lget l; as_non_null; I32 k; call rt "elem"; Lset y ] @ pat_test fc ps.(k) y fail))
  | Pcons { cname; cargs; _ } ->
    let r = Rt.local fc.fb (Rt.nl rt.recd) in
    let want = Array.length cargs in
    [ Lget x; Test (false, T rt.recd); i32_eqz; Br_if fail;
      Lget x; Cast (false, T rt.recd); Lset r;
      Lget r; struct_get rt.recd r_fields; array_len; I32 want; i32_ne; Br_if fail;
      Lget r; struct_get rt.recd r_shape; struct_get rt.shape 0; text rt cname; call rt "bytes_eq"; i32_eqz; Br_if fail ]
    @ List.concat
      (List.init want (fun k ->
           let y = Rt.local fc.fb Rt.v in
           [ Lget r; struct_get rt.recd r_fields; I32 k; array_get rt.vals; Lset y ] @ pat_test fc cargs.(k) y fail))
  | Pstruct fs ->
    (* A struct's fields or a map's keys, by name. *)
    let names = Rt.local fc.fb (Rt.nl rt.vals) and vals = Rt.local fc.fb (Rt.nl rt.vals) and k = Rt.local fc.fb I32 in
    let mp = Rt.local fc.fb (Rt.nl rt.map) in
    [ Rnull (T rt.map); Lset mp;
      Block (Bnone, [
          Lget x; Test (false, T rt.recd);
          If (Bnone, [ Lget x; Cast (false, T rt.recd); struct_get rt.recd r_shape; struct_get rt.shape 1; Lset names;
                       Lget x; Cast (false, T rt.recd); struct_get rt.recd r_fields; Lset vals; Br 1 ], []);
          Lget x; Test (false, T rt.map);
          If (Bnone, [ Lget x; Cast (false, T rt.map); Lset mp; Lget mp; struct_get rt.map m_vals; Lset vals; Br 1 ], []);
          Br (fail + 1) ]) ]
    @ List.concat_map
      (fun (name, q) ->
         let y = Rt.local fc.fb Rt.v in
         [ Lget mp; ref_is_null;
           If (Bval I32, [ Lget names; as_non_null; text rt name; call rt "find_name" ], [ Lget mp; as_non_null; text rt name; call rt "map_find" ]);
           Ltee k; I32 0; i32_lt_s; Br_if fail;
           Lget vals; as_non_null; Lget k; array_get rt.vals; Lset y ] @ pat_test fc q y fail)
      (Array.to_list fs)

and destructure fc e pt v =
  let rt = fc.st.rt in
  let x = Rt.local fc.fb Rt.v in
  match pt with
  | Parray ps ->
    let l = Rt.local fc.fb (Rt.nl rt.list) in
    let want = Array.length ps in
    stored fc v @ [ Lset x; Lget x; Test (false, T rt.list);
                    If (Bnone, [], Rt.fail rt (Messages.destructure_value a1) [ [ Lget x; call rt "describe" ] ] (site fc e.pos));
                    Lget x; Cast (false, T rt.list); Lset l;
                    Lget l; as_non_null; call rt "cells"; I32 want; i32_ne;
                    If (Bnone, Rt.fail rt (Messages.destructure_array want 1000001 |> fun m -> { m with text = replace m.text [ "1000001", a1 ] })
                                 [ [ Lget l; as_non_null; call rt "cells"; i64_extend_u; call rt "itoa" ] ] (site fc e.pos), []) ]
    @ List.concat
      (List.init want (fun k ->
           match ps.(k) with
           | Pname n -> write_var fc n e.pos [ Lget l; as_non_null; I32 k; call rt "elem"; call rt "share" ] V
           | Pwild -> []
           | _ -> unsupported fc e.pos "a nested pattern"))
  | _ -> unsupported fc e.pos "this pattern"

(* x[i] = v, x.Name = v, and paths of them: each level is made owned on the way down, then written back. *)
and set_path fc e root path value =
  let rt = fc.st.rt in
  let rk, get = match root.b with Local i -> var_value fc i | _ -> V, (snd (var fc e root)) in
  if rk <> V then unsupported fc e.pos "a write into a number";
  let steps = Array.to_list path in
  (* The containers along the path: the root, then each level read. *)
  let n = List.length steps in
  let cs = Array.init n (fun _ -> Rt.local fc.fb Rt.v) in
  let vix (st : step) = match st.sk with Sindex ([| Ix i |], _) -> kind fc i <> I | _ -> false in
  let idx = Array.map (fun st -> Rt.local fc.fb (if vix st then Rt.v else I64)) path in
  let read_step j (st : step) =
    match st.sk with
    | Sindex ([| Ix i |], uses_end) ->
      if uses_end then fc.ends <- cs.(j) :: fc.ends;
      let code = (match kind fc i with I -> expr fc i I | _ -> expr fc i V) @ [ Lset idx.(j) ] in
      if uses_end then fc.ends <- List.tl fc.ends;
      code
    | Sindex _ -> unsupported fc st.sp "this index"
    | Sfield _ -> []
  in
  let get_step j (st : step) =
    match st.sk with
    | Sindex _ -> [ Lget cs.(j); Lget idx.(j) ] @ site fc st.sp @ [ call rt (if vix st then "index_v" else "index") ]
    | Sfield name -> [ Lget cs.(j); text rt name; cache rt ] @ site fc st.sp @ [ call rt "field" ]
  in
  let set_step j (st : step) v =
    match st.sk with
    | Sindex _ -> [ Lget cs.(j); Lget idx.(j) ] @ v @ site fc st.sp @ [ call rt (if vix st then "set_index_v" else "set_index") ]
    | Sfield name -> [ Lget cs.(j); text rt name ] @ v @ site fc st.sp @ [ call rt "set_field" ]
  in
  let x = Rt.local fc.fb Rt.v in
  (* The indexes and the value first, as the interpreter evaluates them, then the reads down the path. *)
  let own = if n > 1 then [ call rt "own" ] else [] in
  get @ own @ [ Lset cs.(0) ]
  @ List.concat (List.mapi (fun j st -> (if j > 0 then get_step (j - 1) (List.nth steps (j - 1)) @ own @ [ Lset cs.(j) ] else []) @ read_step j st) steps)
  @ stored fc value @ [ Lset x ]
  @ (let rec back j v = if j < 0 then v else back (j - 1) (set_step j (List.nth steps j) v) in
     back (n - 1) [ Lget x ])
  @ (match root.b with
      | Local i when fc.locs.(i) >= 0 -> [ Lset fc.locs.(i) ]
      | Local i -> [ Gset (cell_global fc.st fc.pm (cell_index fc i)) ]
      | Cell { m; k; _ } -> [ Gset (cell_global fc.st m k) ]
      | Unresolved -> unsupported fc e.pos "an unresolved name")

(* Calls. *)
and call_expr fc e (call : call) : kind * ins list =
  let w = fc.st.w in
  match call.callee.e with
  | Var { b = Cell { m; k; stable = true }; text } ->
    (match w.modules.(m).cells.(k) with
     | Native nat ->
       let key = (w.modules.(m).mname, nat.nname) in
       (match Hashtbl.find_opt natives key with
        | Some f ->
          if Array.exists (fun (a : arg) -> a.aname <> None) call.args then unsupported fc e.pos ("named arguments of " ^ text);
          let k = kind fc e in
          k, f fc (Array.map (fun (a : arg) -> a.value) call.args) e.pos k
        | None -> unsupported fc e.pos (Printf.sprintf "%s.%s" (fst key) nat.nname))
     | Fun { proto; env = [||] } -> static_call fc e call proto
     | _ -> dynamic_call fc e call)
  | _ -> dynamic_call fc e call

and static_call fc e (call : call) (proto : proto) =
  let rt = fc.st.rt in
  let w = fc.st.w in
  let f = Cache.ready proto.func in
  match Infer.bind_args f call.args with
  | Error m -> V, Rt.fail rt m [] (site fc e.pos)
  | Ok slots ->
    let sg = Array.map (function None -> TBot | Some (a : expr) -> fc.ver.tn.(a.id)) slots in
    let v = Infer.version_for w proto sg in
    ready w v;
    let self = v == fc.ver && call.self_tail && fc.tail >= 0 in
    let np = Array.length f.params in
    let args =
      List.concat
        (List.init np (fun k ->
             let pk = kind_of v.tv.(k) in
             match slots.(k) with
             | Some a -> if pk = V then stored fc a else expr fc a pk
             | None -> (match pk with I -> [ i64 0 ] | F -> [ F64 0. ] | V -> [ g_undef rt ])))
    in
    if self then begin
      (* A tail call to itself: a loop, as the interpreter's, which takes no depth. *)
      let temps = List.init np (fun k -> Rt.local fc.fb (vt_of (kind_of v.tv.(k)))) in
      V, args @ List.concat (List.rev_map (fun t -> [ Lset t ]) temps)
         @ List.concat (List.mapi (fun k t -> [ Lget t; Lset k ]) temps)
         @ [ Br (depth_of fc "tail") ]
    end
    else begin
      let name = ver_name fc.st v in
      kind_of v.ret, call_site fc e.pos @ args @ [ Call name ]
    end

(* The site of a call, at the next depth: the trace of an error names it. *)
and call_site fc pos =
  let rt = fc.st.rt in
  [ Gget (depth rt); I32 4; i32_mul ] @ site fc pos @ [ store32 (calls + 4) ]

and dynamic_call fc e (call : call) =
  if Array.exists (fun (a : arg) -> a.aname <> None) call.args then unsupported fc e.pos "named arguments to a function value";
  let n = Array.length call.args in
  let f = Rt.local fc.fb Rt.v in
  V, expr fc call.callee V @ [ Lset f ] @ call_site fc e.pos @ [ Lget f ]
     @ List.concat_map (fun (a : arg) -> stored fc a.value) (Array.to_list call.args)
     @ site fc e.pos @ [ Call (dyn_call fc.st n) ]

(* The call of a function value with n arguments: of its arity, or of fewer when the others have defaults. *)
and dyn_call st n =
  let rt = st.rt in
  let name = "call" ^ string_of_int n in
  if not (Wasm.has_func rt.m name) then begin
    let f = Wasm.func rt.m name (Rt.v :: List.init n (fun _ -> Rt.v) @ [ I32 ]) [ Rt.v ] in
    let fb = { Rt.f; n = 0; rev = []; tmp = -1 } in
    let g = Rt.local fb (Rt.nn rt.fn) in
    let site = n + 1 in
    let most = 8 in
    let arity a = List.init a (fun k -> if k < n then Lget (k + 1) else g_undef rt) in
    f.body <-
      [ Lget 0; Test (false, T rt.fn);
        If (Bnone, [], Rt.fail rt (Messages.not_function a1) [ [ Lget 0; call rt "describe" ] ] [ Lget site ]);
        Lget 0; Cast (false, T rt.fn); Lset g;
        Lget g; struct_get rt.fn f_arity; I32 n; i32_lt_u;
        If (Bnone, Rt.fail rt (Messages.too_many "\003" 1000001 1000002 |> fun m -> { m with text = replace m.text [ "\003", a1; "1000001 arguments", a2; "1000002", string_of_int n ] })
                     [ [ Lget g; struct_get rt.fn f_name ]; [ Lget g; struct_get rt.fn f_arity; i64_extend_u; call rt "itoa" ] ] [ Lget site ], []) ]
      @ List.concat
        (List.init (most - n + 1) (fun d ->
             let a = n + d in
             [ Lget g; struct_get rt.fn f_arity; I32 a; i32_eq;
               If (Bnone, [ Lget g ] @ arity a @ [ Lget g; struct_get rt.fn f_code; Cast (false, T (Rt.fn_type rt a)); Call_ref (Rt.fn_type rt a); ret ], []) ]))
      @ [ unreachable ];
    f.locals <- List.rev fb.rev
  end;
  name

(* A version's function. *)
let compile_version st (v : version) name ~hoisted ~main =
  let rt = st.rt in
  let f = Cache.ready v.owner.func in
  let path = fst (Vec.get st.w.files v.owner.file) in
  if f.ret <> None then raise (Unsupported (path, f.fpos, "a declared result type"));
  Array.iter (fun (p : param) -> if p.ptype <> None then raise (Unsupported (path, f.fpos, "a declared parameter type"))) f.params;
  ready st.w v;
  let ps, rs = signature st v in
  (* A file's level gives nothing that anything reads. *)
  let rs = if main then [ Rt.v ] else rs in
  let wf = Wasm.func rt.m name ps rs in
  let fb = { Rt.f = wf; n = 0; rev = []; tmp = -1 } in
  let np = Array.length f.params in
  let env = if has_env f then 0 else -1 in
  let base = if env >= 0 then 1 else 0 in
  let kinds = Array.init f.nvars (fun i -> kind_of v.tv.(i)) in
  let cells = if f.cell_of = [||] then Array.make f.nvars (-1) else f.cell_of in
  let locs = Array.init f.nvars (fun i -> if cells.(i) >= 0 then -1 else if i < np then base + i else -2) in
  Array.iteri (fun i l -> if l = -2 then locs.(i) <- Rt.local fb (vt_of kinds.(i))) locs;
  (* Parameters are numbered from 0 in the tail loop: they are the first locals after the env. *)
  let fc =
    { st; fb; ver = v; fn = f; path = fst (Vec.get st.w.files v.owner.file); pname = v.owner.pname; file = v.owner.file;
      pm = v.owner.pm; locs; kinds; env; labels = []; ends = []; hoisted; tail = (if main then -1 else 0); exit = None; fixed = [] }
  in
  let rk = if main then V else kind_of v.ret in
  let generic = match v.owner.generic with Some g -> g == v | None -> false in
  let prologue =
    (* Unset variables, captured values, defaults. *)
    List.concat
      (List.init f.nvars (fun i ->
           if locs.(i) >= np + base && kinds.(i) = V && f.maybe_undef.(i) then [ g_undef rt; Lset locs.(i) ] else []))
    @ List.concat (List.mapi (fun j (_, inner) -> [ Lget env; as_non_null; I32 j; array_get rt.vals; Lset locs.(inner) ]) (Array.to_list f.captures))
    @ List.concat
      (List.init np (fun k ->
           match f.params.(k).default with
           | Some d when v.sg.(k) == TBot -> expr fc d kinds.(k) @ [ Lset locs.(k) ]
           | Some d when kinds.(k) = V && (generic || v.sg.(k) == TA) ->
             [ Lget locs.(k); g_undef rt; ref_eq; If (Bnone, expr fc d V @ [ Lset locs.(k) ], []) ]
           | _ -> []))
  in
  let entry = if main then [] else [ I32 (site_at st v.owner.file f.fpos v.owner.pname); call rt "enter" ] @ tick rt in
  let body = Lazy.force f.body in
  let n = Array.length body in
  (* The parameters' copies for a self tail call are the parameters themselves: the tail loop goes around the body. *)
  let code =
    if main then begin
      let stmts = nest fc "tail" (fun () -> List.concat_map (stmt fc) (Array.to_list body)) in
      stmts @ [ missing ] @ convert fc ~from:V ~into:rk
    end
    else
      [ loop fc "tail" (Bval (vt_of rk)) (fun () ->
            List.concat (List.init (max 0 (n - 1)) (fun i -> stmt fc body.(i)))
            @ (if n = 0 then [ missing ] @ convert fc ~from:V ~into:rk else expr fc body.(n - 1) rk)) ]
  in
  (* A file's variables that stayed local go to their cells, for the files that read them. *)
  let exports =
    if main && f.export_of <> [||] then
      List.concat
        (List.init f.nvars (fun i ->
             if i < Array.length f.export_of && f.export_of.(i) >= 0 && cells.(i) < 0 && locs.(i) >= 0 then
               [ Lget locs.(i) ] @ convert fc ~from:kinds.(i) ~into:V @ [ Gset (cell_global st v.owner.pm f.export_of.(i)) ]
             else []))
    else []
  in
  let tmp = Rt.local fb (vt_of rk) in
  wf.body <- prologue @ entry @ code @ [ Lset tmp ] @ exports @ (if main then [] else leave fc) @ [ Lget tmp ];
  wf.locals <- List.rev fb.rev

(* The natives of this slice. *)
let () =
  let reg pkg name f = Hashtbl.replace natives ("std/" ^ pkg, name) f in
  let arity fc pos args n = if Array.length args <> n then unsupported fc pos (Printf.sprintf "this native with %d arguments" (Array.length args)) in
  reg "io" "Print" (fun fc args _ k ->
      let rt = fc.st.rt in
      (* Every argument before the line, as the interpreter: an error in one writes nothing of it. A constant, or a
         variable read while nothing runs after it, is read where it is written; another goes in a local. A text
         written in the call is a constant, whose bytes go out with no test of its type. *)
      let args = List.map (fun a -> let k = kind fc a in (match a.e with Ltext _ -> `T | _ -> `K k), expr fc a k) (Array.to_list args) in
      let pure (t, c) = t = `T || (match c with [ (I64 _ | F64 _ | Rnull _) ] -> true | _ -> false) in
      let read (t, c) = (match c with [ (Lget _ | Gget _) ] -> true | _ -> false) || pure (t, c) in
      let rec keep = function
        | [] -> [], []
        | a :: rest ->
          let sets, reads = keep rest in
          if pure a || (read a && List.for_all read rest) then sets, a :: reads
          else
            let t, c = a in
            let l = Rt.local fc.fb (match t with `K I -> I64 | `K F -> F64 | _ -> Rt.v) in
            (c @ [ Lset l ]) :: sets, (t, [ Lget l ]) :: reads
      in
      let sets, reads = keep args in
      List.concat sets
      @ List.concat
        (List.mapi
           (fun i (t, c) ->
              (if i > 0 then [ I32 32; call rt "out_byte" ] else [])
              @ c @ [ call rt (match t with `T -> "out_bytes" | `K I -> "print_i" | `K F -> "print_f" | `K V -> "print") ])
           reads)
      @ [ I32 10; call rt "out_byte"; missing ] @ convert fc ~from:V ~into:k);
  let int2 name fn =
    reg "math" name (fun fc args pos k ->
        arity fc pos args 2;
        let rt = fc.st.rt in
        let whole a =
          match kind fc a with
          | I -> expr fc a I
          | _ ->
            let x = Rt.local fc.fb Rt.v in
            expr fc a V @ [ Ltee x; call rt "is_int"; If (Bval I64, [ Lget x; call rt "int_of" ], [ Lget x ] @ site fc pos @ [ call rt ("want_int:" ^ name) ]) ]
        in
        if not (Hashtbl.mem Rt.defs ("want_int:" ^ name)) then
          Rt.def ("want_int:" ^ name) (fun rt -> [ Rt.v; I32 ], [ I64 ], fun fb ->
              let x = Rt.local fb F64 in
              [ Lget 0; Test (false, T rt.boxf);
                If (Bnone, [ Lget 0; call rt "float_of"; Lset x; Lget x; f64_trunc; Lget x; f64_eq; Lget x; f64_abs; F64 4e18; f64_lt; i32_and;
                             If (Bnone, [ Lget x; i64_trunc_sat; ret ], []) ], []) ]
              @ Rt.fail rt (Messages.want_int name a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
        match whole args.(1) with
        | [ I64 c ] when c >= 1L ->
          (* By a positive constant: inline, rounded down, so that the engine turns it into a product. *)
          let x = Rt.local fc.fb I64 and r = Rt.local fc.fb I64 in
          whole args.(0) @ [ Ltee x; I64 c; i64_rem_s; Lset r ]
          @ (if name = "Mod" then [ Lget r; i64 0; i64_lt_s; If (Bval I64, [ Lget r; I64 c; i64_add ], [ Lget r ]) ]
             else [ Lget x; I64 c; i64_div_s; Lget r; i64 0; i64_lt_s; i64_extend_u; i64_sub ])
          @ convert fc ~from:I ~into:k
        | b -> whole args.(0) @ b @ site fc pos @ [ call rt fn ] @ convert fc ~from:I ~into:k)
  in
  int2 "Div" "div_i";
  int2 "Mod" "mod_i";
  let math1 name op =
    reg "math" name (fun fc args pos k ->
        arity fc pos args 1;
        let rt = fc.st.rt in
        match kind fc args.(0) with
        | I | F -> expr fc args.(0) F @ op rt @ convert fc ~from:F ~into:k
        | V ->
          let g = "math1:" ^ name in
          if not (Hashtbl.mem Rt.defs g) then
            Rt.def g (fun rt -> [ Rt.v; I32 ], [ Rt.v ], fun _ ->
                [ Lget 0; ref_is_null; If (Bnone, [ missing; ret ], []);
                  Lget 0; call rt "kind"; I32 1; i32_le_u; If (Bnone, [ Lget 0; call rt "as_float" ] @ op rt @ [ call rt "box_f"; ret ], []) ]
                @ Rt.need_number rt name 0 1);
          expr fc args.(0) V @ site fc pos @ [ call rt g ] @ convert fc ~from:V ~into:k)
  in
  math1 "Sqrt" (fun _ -> [ f64_sqrt ]);
  List.iter (fun (n, js) -> math1 n (fun rt -> [ host rt js ]))
    [ "Exp", "exp"; "Log", "log"; "Sin", "sin"; "Cos", "cos"; "Tan", "tan"; "Asin", "asin"; "Acos", "acos"; "Atan", "atan" ];
  reg "math" "Abs" (fun fc args pos k ->
      arity fc pos args 1;
      let rt = fc.st.rt in
      match kind fc args.(0) with
      | F -> expr fc args.(0) F @ [ f64_abs ] @ convert fc ~from:F ~into:k
      | I ->
        let x = Rt.local fc.fb I64 in
        expr fc args.(0) I @ [ Lset x; Lget x; i64 0; i64_lt_s; If (Bval I64, [ Lget x ] @ site fc pos @ [ call rt "neg_i" ], [ Lget x ]) ] @ convert fc ~from:I ~into:k
      | V -> expr fc args.(0) V @ site fc pos @ [ call rt "abs_v" ] @ convert fc ~from:V ~into:k);
  let rounding name op =
    reg "math" name (fun fc args pos k ->
        arity fc pos args 1;
        match kind fc args.(0) with
        | F -> expr fc args.(0) F @ op fc.fb @ convert fc ~from:F ~into:k
        | I -> expr fc args.(0) I @ convert fc ~from:I ~into:k
        | V -> expr fc args.(0) V @ site fc pos @ [ call fc.st.rt (String.lowercase_ascii name ^ "_v") ] @ convert fc ~from:V ~into:k)
  in
  rounding "Floor" (fun _ -> [ f64_floor ]);
  rounding "Ceil" (fun _ -> [ f64_ceil ]);
  rounding "Round" Rt.round_f;
  reg "value" "Len" (fun fc args pos k ->
      arity fc pos args 1;
      expr fc args.(0) V @ [ call fc.st.rt "len" ] @ convert fc ~from:I ~into:k);
  reg "value" "Text" (fun fc args pos k ->
      arity fc pos args 1;
      expr fc args.(0) V @ [ call fc.st.rt "text_of" ] @ convert fc ~from:V ~into:k);
  reg "value" "Equal" (fun fc args pos k ->
      arity fc pos args 2;
      let rt = fc.st.rt in
      expr fc args.(0) V @ expr fc args.(1) V @ [ call rt "equal" ] @ bool_of rt @ convert fc ~from:V ~into:k);
  let filled pkg name fill =
    reg pkg name (fun fc args pos k ->
        let rt = fc.st.rt in
        let x, size = match fill, args with Some x, [| n |] -> x, n | None, [| x; n |] -> stored fc x, n | _ -> unsupported fc pos "these sizes" in
        let g = "fill" in
        if not (Hashtbl.mem Rt.defs g) then
          Rt.def g (fun rt -> [ Rt.v; I64; I32 ], [ Rt.v ], fun fb ->
              let n = Rt.local fb I32 and i = Rt.local fb I32 and w = Rt.local fb (Rt.nn rt.vals) in
              [ Lget 1; i64 0; i64_lt_s; Lget 1; i64 (1 lsl 28); i64_gt_s; i32_or;
                If (Bnone, Rt.fail rt Messages.range_too_long [] [ Lget 2 ], []);
                Lget 1; i32_wrap; Lset n; Lget n; array_new_default rt.vals; Lset w ]
              @ upto i n [ Lget w; Lget i; Lget 0; array_set rt.vals ]
              @ [ Lget n; If (Bval I32, [ I32 1 ], [ I32 1 ]); Lget n; Lget w; call rt "list_of" ]);
        x @ (match kind fc size with I -> expr fc size I | _ -> expr fc size V @ site fc pos @ [ call rt "range_bound" ]) @ site fc pos @ [ call rt g ]
        @ convert fc ~from:V ~into:k)
  in
  reg "list" "Sum" (fun fc args pos k ->
      arity fc pos args 1;
      expr fc args.(0) V @ site fc pos @ [ call fc.st.rt "sum" ] @ convert fc ~from:V ~into:k);
  reg "list" "Append" (fun fc args pos k ->
      arity fc pos args 2;
      expr fc args.(0) V @ expr fc args.(1) V @ site fc pos @ [ call fc.st.rt "append" ] @ convert fc ~from:V ~into:k);
  reg "list" "Concat" (fun fc args pos k ->
      arity fc pos args 2;
      expr fc args.(0) V @ expr fc args.(1) V @ site fc pos @ [ call fc.st.rt "concat" ] @ convert fc ~from:V ~into:k);
  List.iter
    (fun (name, f) ->
       reg "list" name (fun fc args pos k ->
           arity fc pos args 2;
           expr fc args.(0) V @ expr fc args.(1) V @ site fc pos @ [ call fc.st.rt f ] @ convert fc ~from:V ~into:k))
    [ "Take", "take"; "Skip", "skip" ];
  reg "list" "Reverse" (fun fc args pos k ->
      arity fc pos args 1;
      expr fc args.(0) V @ site fc pos @ [ call fc.st.rt "reverse" ] @ convert fc ~from:V ~into:k);
  reg "value" "Size" (fun fc args pos k ->
      arity fc pos args 1;
      expr fc args.(0) V @ [ call fc.st.rt "size" ] @ convert fc ~from:V ~into:k);
  reg "matrix" "Reshape" (fun fc args pos k ->
      arity fc pos args 2;
      expr fc args.(0) V @ expr fc args.(1) V @ site fc pos @ [ call fc.st.rt "reshape" ] @ convert fc ~from:V ~into:k);
  reg "bug" "Panic" (fun fc args pos k ->
      arity fc pos args 1;
      expr fc args.(0) V @ site fc pos @ [ call fc.st.rt "panic" ] @ convert fc ~from:V ~into:k);
  let is name test =
    reg "value" name (fun fc args pos k ->
        arity fc pos args 1;
        let rt = fc.st.rt in
        expr fc args.(0) V @ test rt @ bool_of rt @ convert fc ~from:V ~into:k)
  in
  is "IsInt" (fun rt -> [ call rt "is_int" ]);
  is "IsFloat" (fun rt -> [ Test (false, T rt.boxf) ]);
  is "IsNumber" (fun rt -> let x = "is_number" in
                  if not (Hashtbl.mem Rt.defs x) then Rt.def x (fun rt -> [ Rt.v ], [ I32 ], fun _ -> [ Lget 0; call rt "is_int"; Lget 0; Test (false, T rt.boxf); i32_or ]);
                  [ call rt x ]);
  is "IsText" (fun rt -> [ Test (false, T rt.bytes) ]);
  is "IsArray" (fun rt -> [ Test (false, T rt.list) ]);
  is "IsDict" (fun rt -> [ Test (false, T rt.map) ]);
  is "IsStruct" (fun rt -> [ Test (false, T rt.recd) ]);
  is "IsFunction" (fun rt -> [ Test (false, T rt.fn) ]);
  is "IsMissing" (fun _ -> [ ref_is_null ]);
  is "IsBool" (fun rt -> let x = "is_bool" in
                if not (Hashtbl.mem Rt.defs x) then Rt.def x (fun rt -> [ Rt.v ], [ I32 ], fun _ -> [ Lget 0; g_true rt; ref_eq; Lget 0; g_false rt; ref_eq; i32_or ]);
                [ call rt x ]);
  filled "list" "Fill" None;
  filled "matrix" "Zeros" (Some [ F64 0.; Call "box_f" ]);
  filled "matrix" "Ones" (Some [ F64 1.; Call "box_f" ])

(* The program: its files, in the order the interpreter runs them, become the start of the module. *)
let build (w : world) (prepared : (int * int * Ast.func * layout) list) =
  let rt = Rt.create () in
  let st = { w; rt; sites = Vec.create (); site_ids = Hashtbl.create 256; vers = []; todo = []; lambdas = []; counter = 0; values = [] } in
  ignore (need rt "box_f");
  let hoisted = List.concat_map (fun (_, _, _, (l : layout)) -> List.map snd (Array.to_list l.hoisted)) prepared in
  List.iter
    (fun (file, _, (fn : Ast.func), (l : layout)) ->
       let path = fst (Vec.get w.files file) in
       if l.methods <> [] then raise (Unsupported (path, fn.fpos, "a method"));
       if l.interfaces <> [] then raise (Unsupported (path, fn.fpos, "an interface")))
    prepared;
  let mains =
    List.filter_map
      (fun (file, m, (fn : Ast.func), _) ->
         let body = Lazy.force fn.body in
         let quiet (e : expr) = match e.e with Use _ | Interface _ | Fn_def ({ b = Cell _; _ }, _) -> true | Fn_def (_, f) -> List.memq f hoisted | _ -> false in
         if Array.for_all quiet body then None
         else begin
           let proto = Compile.new_proto ~file ~m fn in
           let v = Infer.make_version proto [||] in
           proto.versions <- [ v ];
           Infer.run w v;
           st.counter <- st.counter + 1;
           let name = Printf.sprintf "main%d" st.counter in
           compile_version st v name ~hoisted ~main:true;
           Some name
         end)
      prepared
  in
  let rec drain () =
    match st.todo with
    | [] -> ()
    | v :: rest ->
      st.todo <- rest;
      compile_version st v (List.assq v st.vers) ~hoisted ~main:false;
      drain ()
  in
  drain ();
  let start = Wasm.func rt.m "main" [] [] in
  start.body <- rt.inits @ List.concat_map (fun n -> [ Call n; drop ]) mains @ [ call rt "flush" ];
  drain ();
  Wasm.export rt.m "main" "main";
  let sites = Buffer.create 4096 in
  Buffer.add_char sites '[';
  for i = 0 to Vec.length st.sites - 1 do
    if i > 0 then Buffer.add_char sites ',';
    Buffer.add_string sites (Vec.get st.sites i)
  done;
  Buffer.add_char sites ']';
  Wasm.custom rt.m "cesia.sites" (Buffer.contents sites);
  Wasm.write rt.m
