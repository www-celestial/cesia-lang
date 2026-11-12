open Ast

(* Below this, the sources parse faster than their entry is found, read and checked. *)
let least = 512

type store = { build : string; read : string -> string option; write : string -> string -> unit }

let store = ref None

type slot = { name : string; kept : store; nesting : int; digests : string list }
type place = { first : int; count : int; natives : int option; used : int array; package : int -> int array }
type use = { upath : string; ualias : string; upos : Pos.t; unames : string list }

(* An entry that isn't what it should be: it is not used. *)
exception Bad

(* A source of the binary itself changes only with the build: it needs no digest. *)
let slot ~key ~nesting ~fixed sources =
  match !store with
  | Some kept when List.fold_left (fun n (_, s) -> n + String.length s) 0 sources >= least ->
    let digest (_, src) = if fixed src then "" else Digest.BLAKE128.string src in
    let name = Digest.BLAKE128.to_hex (Digest.BLAKE128.string key) in
    Some { name; kept; nesting; digests = List.map digest sources }
  | _ -> None

(* The module numbers of a binding, relative to the package: (0, 0) the core, (1, j) its file j or, at j = count, its
   natives, (u + 2, j) the module j of the package of its use u. *)
let rel p m =
  if m = 0 then 0, 0
  else if m >= p.first && m < p.first + p.count then 1, m - p.first
  else if p.natives = Some m then 1, p.count
  else
    let rec dep u =
      if u >= Array.length p.used then raise Exit
      else
        match if p.used.(u) < 0 then None else Array.find_index (Int.equal m) (p.package p.used.(u)) with
        | Some j -> u + 2, j
        | None -> dep (u + 1)
    in
    dep 0

(* Each module is placed once: every module a package names comes before its own last one. *)
let memo p =
  let seen = Array.make (p.first + p.count + 1) None in
  fun m ->
    if m < 0 || m >= Array.length seen then rel p m
    else match seen.(m) with Some r -> r | None -> let r = rel p m in seen.(m) <- Some r; r

let abs p u j =
  match u with
  | 0 when j = 0 -> 0
  | 1 when j >= 0 && j < p.count -> p.first + j
  | 1 when j = p.count -> (match p.natives with Some n -> n | None -> raise Bad)
  | _ when u >= 2 && u - 2 < Array.length p.used ->
    let modules = p.package p.used.(u - 2) in
    if j >= 0 && j < Array.length modules then modules.(j) else raise Bad
  | _ -> raise Bad

(* An entry: these 8 bytes, the BLAKE2b-128 of the rest, then the rest. *)
let magic = "Cesia\000L1"

(* Writing. The strings of an entry are each written once, then by their number. *)
module Out = struct
  (* A place is written as its distance from the one before, most often a byte. *)
  type out = {
    mutable b : Bytes.t;
    mutable n : int;
    strings : (string, int) Hashtbl.t;
    rel : int -> int * int;
    mutable last : int;
  }

  let grow o k =
    let b = Bytes.create (2 * (Bytes.length o.b + k)) in
    Bytes.blit o.b 0 b 0 o.n;
    o.b <- b

  let[@inline] byte o c =
    if o.n = Bytes.length o.b then grow o 1;
    Bytes.set o.b o.n (Char.chr c);
    o.n <- o.n + 1
  let rec uint o n = if n land lnot 127 = 0 then byte o n else (byte o (n land 127 lor 128); uint o (n lsr 7))
  let int o n = uint o ((n lsl 1) lxor (n asr 62))
  let bool o x = byte o (if x then 1 else 0)
  let pos o p = int o (p - o.last); o.last <- p

  let str o s =
    match Hashtbl.find_opt o.strings s with
    | Some i -> uint o ((2 * i) + 1)
    | None ->
      Hashtbl.add o.strings s (Hashtbl.length o.strings);
      uint o (2 * String.length s);
      let k = String.length s in
      if o.n + k > Bytes.length o.b then grow o k;
      Bytes.blit_string s 0 o.b o.n k;
      o.n <- o.n + k

  let opt f o = function None -> byte o 0 | Some x -> byte o 1; f o x
  let arr f o a = uint o (Array.length a); Array.iter (f o) a
  let list f o l = uint o (List.length l); List.iter (f o) l

  let binding o = function
    | Unresolved -> byte o 0
    | Local i -> byte o 1; uint o i
    | Cell { m; k; stable } ->
      let u, j = o.rel m in
      byte o (if stable then 3 else 2);
      uint o u;
      uint o j;
      uint o k

  let name o (n : name) = str o n.text; binding o n.b
  let binop o op =
    byte o (match op with Add -> 0 | Sub -> 1 | Mul -> 2 | Div -> 3 | Pow -> 4 | Eq -> 5 | Ne -> 6 | Lt -> 7 | Le -> 8 | Gt -> 9 | Ge -> 10)

  let ptype o t =
    pos o t.tpos; opt str o t.tpkg; str o t.tname; bool o t.topt; bool o t.tbang; binding o t.tb

  let rec expr o (x : expr) = uint o x.id; pos o x.pos; node o x.e

  and block o b = arr expr o b

  and node o = function
    | Lint n -> byte o 0; int o n
    | Lfloat x ->
      byte o 1;
      if o.n + 8 > Bytes.length o.b then grow o 8;
      Bytes.set_int64_le o.b o.n (Int64.bits_of_float x);
      o.n <- o.n + 8
    | Lbool x -> byte o 2; bool o x
    | Lmissing -> byte o 3
    | Ltext s -> byte o 4; str o s
    | Interp parts ->
      byte o 5;
      arr (fun o -> function Lit s -> byte o 0; str o s | Hole e -> byte o 1; expr o e) o parts
    | Var n -> byte o 6; name o n
    | Bin (op, a, b) -> byte o 7; binop o op; expr o a; expr o b
    | Neg a -> byte o 8; expr o a
    | Not a -> byte o 9; expr o a
    | And (a, b) -> byte o 10; expr o a; expr o b
    | Or (a, b) -> byte o 11; expr o a; expr o b
    | Call c ->
      byte o 12;
      expr o c.callee;
      arr (fun o (a : arg) -> opt str o a.aname; expr o a.value) o c.args;
      bool o c.self_tail
    | Assign (n, v) -> byte o 13; name o n; expr o v
    | If (c, a, b) -> byte o 14; expr o c; block o a; block o b
    | While { cond; body; has_break } -> byte o 15; expr o cond; block o body; bool o has_break
    | Break -> byte o 16
    | Return r -> byte o 17; opt expr o r.rvalue; bool o r.tail
    | Lambda f -> byte o 18; func o f
    | Fn_def (n, f) -> byte o 19; name o n; func o f
    | Range (a, b) -> byte o 20; expr o a; expr o b
    | In_op (a, b) -> byte o 21; expr o a; expr o b
    | Array_lit rows -> byte o 22; arr block o rows
    | Comp { cbody; cvar; csrc; cguard } -> byte o 23; expr o cbody; name o cvar; expr o csrc; opt expr o cguard
    | Index (b, ixs, u) -> byte o 24; expr o b; arr index o ixs; bool o u
    | Field (b, s) -> byte o 25; expr o b; str o s
    | Struct_lit { sname; sfields } -> byte o 26; opt str o sname; arr (fun o (s, e) -> str o s; expr o e) o sfields
    | End_index -> byte o 27
    | For { var; iter; fbody; f_break } -> byte o 28; name o var; expr o iter; block o fbody; bool o f_break
    | Set { root; path; value } ->
      byte o 29;
      name o root;
      let step o s =
        pos o s.sp;
        match s.sk with Sindex (ixs, u) -> byte o 0; arr index o ixs; bool o u | Sfield f -> byte o 1; str o f
      in
      arr step o path;
      expr o value
    | Destructure (p, v) -> byte o 30; pat o p; expr o v
    | Match { subject; arms } ->
      byte o 31; expr o subject; arr (fun o a -> pat o a.pt; opt expr o a.guard; expr o a.abody) o arms
    | Use { upath; ualias } -> byte o 32; str o upath; str o ualias
    | Interface i -> byte o 33; iface o i
    | Question a -> byte o 34; expr o a
    | Hook h -> byte o 35; str o (Bytes.to_string h.live)

  and index o = function All -> byte o 0 | Ix e -> byte o 1; expr o e

  and pat o = function
    | Pname n -> byte o 0; name o n
    | Pwild -> byte o 1
    | Plit e -> byte o 2; expr o e
    | Parray ps -> byte o 3; arr pat o ps
    | Pstruct fs -> byte o 4; arr (fun o (s, p) -> str o s; pat o p) o fs
    | Pcons c -> byte o 5; opt str o c.cpkg; str o c.cname; arr pat o c.cargs; pos o c.cpos

  and param o p = str o p.pname; opt expr o p.default; opt ptype o p.ptype

  and iface o i = str o i.iname; arr (fun o (s, ps, r) -> str o s; arr param o ps; opt ptype o r) o i.imethods

  and func o f =
    str o f.fname; arr param o f.params; opt ptype o f.ret; block o f.body; uint o f.nnodes; pos o f.fpos;
    uint o f.nvars; arr str o f.var_names; arr (fun o (a, b) -> uint o a; uint o b) o f.captures;
    arr bool o f.maybe_undef; bool o f.has_return; bool o f.has_self_tail; int o f.kept; arr int o f.cell_of;
    arr int o f.export_of

  let use o u = str o u.upath; str o u.ualias; pos o u.upos; list str o u.unames

  (* A hoisted function or an interface is the one of a definition of the file: it is kept as its place in the body, so
     that it stays the same value once read. They come in the order of the body. *)
  let layout o (fn : func) (l : layout) =
    let at = ref 0 in
    let place found =
      while !at < Array.length fn.body && not (found fn.body.(!at).e) do incr at done;
      if !at = Array.length fn.body then raise Exit;
      uint o !at
    in
    arr str o l.cell_names;
    arr (fun o (k, f) -> uint o k; place (function Fn_def (_, g) -> g == f | _ -> false)) o l.hoisted;
    list (fun o (s, n, static, k) -> str o s; str o n; bool o static; uint o k) o l.methods;
    at := 0;
    list (fun o (k, i) -> uint o k; place (function Interface j -> j == i | _ -> false)) o l.interfaces

end

(* Reading, with every count and number checked against what is left: a wrong entry raises, never more. *)
module In = struct
  type inp = { s : string; mutable p : int; strs : string Vec.t; mutable abs : int -> int -> int; mutable last : int }

  let[@inline] byte d =
    let c = Char.code d.s.[d.p] in
    d.p <- d.p + 1;
    c

  let rec more d acc shift =
    let c = byte d in
    if c < 128 then acc lor (c lsl shift)
    else if shift > 56 then raise Bad
    else more d (acc lor ((c land 127) lsl shift)) (shift + 7)

  let[@inline] uint d = let c = byte d in if c < 128 then c else more d (c land 127) 7

  let[@inline] int d = let z = uint d in (z lsr 1) lxor -(z land 1)
  let pos d = let p = d.last + int d in d.last <- p; p
  let[@inline] bool d = match byte d with 0 -> false | 1 -> true | _ -> raise Bad
  let count d = let n = uint d in if n < 0 || n > String.length d.s - d.p then raise Bad else n

  let str d =
    let z = uint d in
    if z land 1 = 1 then Vec.get d.strs (z lsr 1)
    else
      let n = z lsr 1 in
      if n > String.length d.s - d.p then raise Bad;
      let s = String.sub d.s d.p n in
      d.p <- d.p + n;
      Vec.add_last d.strs s;
      s

  let opt f d = match byte d with 0 -> None | 1 -> Some (f d) | _ -> raise Bad
  let arr f d = let n = count d in Array.init n (fun _ -> f d)
  let list f d = let n = count d in List.init n (fun _ -> f d)

  let binding d =
    match byte d with
    | 0 -> Unresolved
    | 1 -> Local (uint d)
    | (2 | 3) as t ->
      let u = uint d in
      let j = uint d in
      let k = uint d in
      Cell { m = d.abs u j; k; stable = t = 3 }
    | _ -> raise Bad

  let name d = let text = str d in let b = binding d in { text; b }
  let binops = [| Add; Sub; Mul; Div; Pow; Eq; Ne; Lt; Le; Gt; Ge |]
  let binop d = let i = byte d in if i < Array.length binops then binops.(i) else raise Bad

  let ptype d =
    let tpos = pos d in
    let tpkg = opt str d in
    let tname = str d in
    let topt = bool d in
    let tbang = bool d in
    let tb = binding d in
    { tpos; tpkg; tname; topt; tbang; tb }

  let rec expr d =
    let id = uint d in
    let pos = pos d in
    let e = node d in
    { id; pos; e }

  (* Most blocks hold one or two expressions: an array written out costs no call of the runtime. *)
  and block d =
    match count d with
    | 0 -> [||]
    | 1 -> [| expr d |]
    | 2 -> let a = expr d in let b = expr d in [| a; b |]
    | n ->
      let a = expr d in
      let b = Array.make n a in
      for i = 1 to n - 1 do b.(i) <- expr d done;
      b

  and two d = let a = expr d in let b = expr d in a, b

  and node d =
    match byte d with
    | 0 -> Lint (int d)
    | 1 ->
      let x = String.get_int64_le d.s d.p in
      d.p <- d.p + 8;
      Lfloat (Int64.float_of_bits x)
    | 2 -> Lbool (bool d)
    | 3 -> Lmissing
    | 4 -> Ltext (str d)
    | 5 -> Interp (arr (fun d -> match byte d with 0 -> Lit (str d) | 1 -> Hole (expr d) | _ -> raise Bad) d)
    | 6 -> Var (name d)
    | 7 -> let op = binop d in let a, b = two d in Bin (op, a, b)
    | 8 -> Neg (expr d)
    | 9 -> Not (expr d)
    | 10 -> let a, b = two d in And (a, b)
    | 11 -> let a, b = two d in Or (a, b)
    | 12 ->
      let callee = expr d in
      let args = arr (fun d -> let aname = opt str d in let value = expr d in ({ aname; value } : arg)) d in
      let self_tail = bool d in
      Call { callee; args; self_tail }
    | 13 -> let n = name d in Assign (n, expr d)
    | 14 -> let c = expr d in let a = block d in let b = block d in If (c, a, b)
    | 15 -> let cond = expr d in let body = block d in let has_break = bool d in While { cond; body; has_break }
    | 16 -> Break
    | 17 -> let rvalue = opt expr d in let tail = bool d in Return { rvalue; tail }
    | 18 -> Lambda (func d)
    | 19 -> let n = name d in Fn_def (n, func d)
    | 20 -> let a, b = two d in Range (a, b)
    | 21 -> let a, b = two d in In_op (a, b)
    | 22 -> Array_lit (arr block d)
    | 23 ->
      let cbody = expr d in
      let cvar = name d in
      let csrc = expr d in
      let cguard = opt expr d in
      Comp { cbody; cvar; csrc; cguard }
    | 24 -> let b = expr d in let ixs = arr index d in let u = bool d in Index (b, ixs, u)
    | 25 -> let b = expr d in Field (b, str d)
    | 26 ->
      let sname = opt str d in
      let sfields = arr (fun d -> let s = str d in s, expr d) d in
      Struct_lit { sname; sfields }
    | 27 -> End_index
    | 28 ->
      let var = name d in
      let iter = expr d in
      let fbody = block d in
      let f_break = bool d in
      For { var; iter; fbody; f_break }
    | 29 ->
      let root = name d in
      let step d =
        let sp = pos d in
        let sk =
          match byte d with
          | 0 -> let ixs = arr index d in Sindex (ixs, bool d)
          | 1 -> Sfield (str d)
          | _ -> raise Bad
        in
        { sp; sk }
      in
      let path = arr step d in
      let value = expr d in
      Set { root; path; value }
    | 30 -> let p = pat d in Destructure (p, expr d)
    | 31 ->
      let subject = expr d in
      let arm d = let pt = pat d in let guard = opt expr d in let abody = expr d in { pt; guard; abody } in
      let arms = arr arm d in
      Match { subject; arms }
    | 32 -> let upath = str d in let ualias = str d in Use { upath; ualias }
    | 33 -> Interface (iface d)
    | 34 -> Question (expr d)
    | 35 -> Hook { live = Bytes.of_string (str d) }
    | _ -> raise Bad

  and index d = match byte d with 0 -> All | 1 -> Ix (expr d) | _ -> raise Bad

  and pat d =
    match byte d with
    | 0 -> Pname (name d)
    | 1 -> Pwild
    | 2 -> Plit (expr d)
    | 3 -> Parray (arr pat d)
    | 4 -> Pstruct (arr (fun d -> let s = str d in s, pat d) d)
    | 5 ->
      let cpkg = opt str d in
      let cname = str d in
      let cargs = arr pat d in
      let cpos = pos d in
      Pcons { cpkg; cname; cargs; cpos }
    | _ -> raise Bad

  and param d =
    let pname = str d in
    let default = opt expr d in
    let ptype = opt ptype d in
    { pname; default; ptype }

  and iface d =
    let iname = str d in
    let imethods = arr (fun d -> let s = str d in let ps = arr param d in s, ps, opt ptype d) d in
    { iname; imethods }

  and func d =
    let fname = str d in
    let params = arr param d in
    let ret = opt ptype d in
    let body = block d in
    let nnodes = uint d in
    let fpos = pos d in
    let nvars = uint d in
    let var_names = arr str d in
    let captures = arr (fun d -> let a = uint d in a, uint d) d in
    let maybe_undef = arr bool d in
    let has_return = bool d in
    let has_self_tail = bool d in
    let kept = int d in
    let cell_of = arr int d in
    let export_of = arr int d in
    { fname; params; ret; body; nnodes; fpos; nvars; var_names; captures; maybe_undef; has_return; has_self_tail; kept;
      cell_of; export_of }

  let use d =
    let upath = str d in
    let ualias = str d in
    let upos = pos d in
    let unames = list str d in
    { upath; ualias; upos; unames }

  let layout d (fn : func) =
    let cell_names = arr str d in
    let at d = let i = uint d in if i < Array.length fn.body then fn.body.(i).e else raise Bad in
    let hoisted = arr (fun d -> let k = uint d in match at d with Fn_def (_, f) -> k, f | _ -> raise Bad) d in
    let methods = list (fun d -> let s = str d in let n = str d in let static = bool d in s, n, static, uint d) d in
    let interfaces = list (fun d -> let k = uint d in match at d with Interface i -> k, i | _ -> raise Bad) d in
    { cell_names; hoisted; methods; interfaces }

end

(* The questions of a resolve, each once, with its answer. *)
type question = Lookup of string | Space of int * string * string

type log = { found : (question, binding option) Hashtbl.t; types : (binding, bool) Hashtbl.t }

let log () = { found = Hashtbl.create 64; types = Hashtbl.create 16 }

let lookup log f text =
  let b = f text in
  Hashtbl.replace log.found (Lookup text) b;
  b

let space log i alias f name =
  let b = f name in
  Hashtbl.replace log.found (Space (i, alias, name)) b;
  b

let is_type log f b =
  let t = f b in
  Hashtbl.replace log.types b t;
  t

type saved = { d : In.inp; uses : use list array }

let uses saved = saved.uses

(* Nothing of an entry is decoded before its digest and what it was made from, the build, the nesting limit and the digest
   of each source, are those expected. *)
let read slot =
  match slot.kept.read slot.name with
  | None -> None
  | Some s ->
    try
      if String.length s < 24 || not (String.starts_with ~prefix:magic s)
         || not (String.equal (String.sub s 8 16) (Digest.BLAKE128.substring s 24 (String.length s - 24)))
      then raise Bad;
      let open In in
      let d = { s; p = 24; strs = Vec.create (); abs = (fun _ _ -> raise Bad); last = 0 } in
      let same = String.equal (str d) slot.kept.build && uint d = slot.nesting && list str d = slot.digests in
      if same then Some { d; uses = arr (list use) d } else None
    with Bad | Invalid_argument _ | Failure _ | Stack_overflow -> None

let trees saved place ~lookup ~spaces ~is_type =
  let open In in
  let d = saved.d in
  d.abs <- abs place;
  let rec asked n =
    n = 0
    ||
    let same =
      match byte d with
      | 0 -> let text = str d in opt binding d = lookup text
      | 1 ->
        let i = uint d in
        let alias = str d in
        let name = str d in
        let b = opt binding d in
        (match List.assoc_opt alias spaces.(i) with Some look -> look name = b | None -> false)
      | 2 -> let b = binding d in bool d = is_type b
      | _ -> raise Bad
    in
    same && asked (n - 1)
  in
  try if asked (count d) then Some (list (fun d -> let fn = func d in fn, layout d fn) d) else None
  with Bad | Invalid_argument _ | Failure _ | Stack_overflow -> None

let write slot place log uses trees =
  let open Out in
  let o = { b = Bytes.create 65536; n = 0; strings = Hashtbl.create 1024; rel = memo place; last = 0 } in
  try
    str o slot.kept.build;
    uint o slot.nesting;
    list str o slot.digests;
    arr (list use) o uses;
    uint o (Hashtbl.length log.found + Hashtbl.length log.types);
    Hashtbl.iter
      (fun q b ->
         match q with
         | Lookup text -> byte o 0; str o text; opt binding o b
         | Space (i, alias, name) -> byte o 1; uint o i; str o alias; str o name; opt binding o b)
      log.found;
    Hashtbl.iter (fun b t -> byte o 2; binding o b; bool o t) log.types;
    list (fun o (fn, l) -> func o fn; layout o fn l) o trees;
    let body = Bytes.sub_string o.b 0 o.n in
    slot.kept.write slot.name (String.concat "" [ magic; Digest.BLAKE128.string body; body ])
  with Exit -> ()
