(* The runtime of Cesia compiled to WebAssembly: its values as WasmGC objects, and the functions that work on them, each
   added to the module at its first use, so that a page holds only what its program needs.

   Values. Every value is an eqref: [missing] the null reference; an integer of Cesia's 63 bits an i31ref when it fits in
   31 bits, else a struct of one i64, so that two equal integers are equal references or both boxed; a float a struct of
   one f64; true, false and the value of an unset variable three atoms; a text its bytes, an array of i8, in UTF-8; an
   array of Cesia (a list, a matrix) a struct of its ownership, rows, columns and store, an array of f64, of i64 or of
   values, as the interpreter's F, I and V stores; a map a struct of its ownership, its keys, its values, its count and
   whether its keys are its alone, the keys shared by the maps of one literal: their names in the order of insertion and,
   past 8 names, a table that finds a name by its hash; a struct of Cesia a struct of its ownership, its shape and its fields; a function a struct
   of its code, its arity, its least arity, its name and its captured values.

   Owned. A list, map or struct is owned while nothing else holds it, as the interpreter's [a_owned]: a write changes an
   owned one in place, and copies one that isn't. The compiler shares a value where the interpreter does.

   Errors. An error writes its message and hint for the loader, by [write] on the streams 3 and 4, then calls [fail]
   with its site and the depth of the calls, whose sites are in the memory: the loader writes the error as Cesia does,
   from the table of sites that the compiler puts in the custom section cesia.sites, and stops the program.

   Memory, two pages: the output's buffer from 0, a scratch area from [scratch], the call sites from [calls], one i32 per
   depth, and in the second page the window through which texts cross to JavaScript and back.

   Fibers. A fiber is a struct of its parks (odd while it waits: a wake that holds the same count resumes it, once), its
   cancel, its timer's mark, the depth and call sites it had when it parked, and its task; a channel a struct of its
   values, its size, the receivers and senders that wait on it, each with the count of their park. The scheduler is the
   loader's: [park] suspends the fiber's whole stack by JSPI, [wake] queues it again. *)

open Wasm

let out_cap = 16384
let scratch = 16384
let calls = 20480
let max_depth = 10_000
(* The fuel: a checkpoint every [fuel_period] steps, at which the page may get the event loop back, and every [full_every]
   of them a full one, at the interpreter's million steps, where the fibers ready run. *)
let fuel_period = 62_500
let full_every = 16
let window = 65536
let v = Ref (true, Eq)

type t = {
  m : Wasm.t;
  bytes : int;
  vals : int;
  f64s : int;
  i64s : int;
  boxi : int;
  boxf : int;
  atom : int;
  own : int;
  list : int;
  keys : int;
  map : int;
  smap : int;
  shape : int;
  recd : int;
  fn : int;
  buf : int;
  cache : int;
  i32s : int;
  fib : int;
  tok : int;
  q : int;
  chan : int;
  sender : int;
  task : int;
  fns : (int, int) Hashtbl.t;  (* arity to the type of a function value's code *)
  texts : (string, string) Hashtbl.t;  (* constant texts: their globals *)
  mutable inits : ins list;  (* what the start makes: long texts *)
}

let nn i = Ref (false, T i)
let nl i = Ref (true, T i)

let create () =
  let m = Wasm.create () in
  m.memory <- 2;
  let bytes = fresh_ty m (Ar (I8, true)) in
  let vals = fresh_ty m (Ar (S v, true)) in
  let f64s = fresh_ty m (Ar (S F64, true)) in
  let i64s = fresh_ty m (Ar (S I64, true)) in
  let boxi = fresh_ty m (St [ S I64, false ]) in
  let boxf = fresh_ty m (St [ S F64, false ]) in
  let atom = fresh_ty m (St [ S I32, false ]) in
  (* What a value may own, first of a list, map or struct: its ownership, so that one test shares any of them. *)
  let own = Wasm.sub_ty m ~final:false [] (St [ S I32, true ]) in
  let owned c = Wasm.sub_ty m ~final:true [ own ] c in
  (* tip: no Append went on from this list yet, so the free cells of its store after its last are still free. *)
  let list = owned (St [ S I32, true; S I32, true; S I32, true; S (Ref (false, Array)), true; S I32, true ]) in
  (* Keys: their names, from the first in the order of insertion; past 8 names, the slots of a table, each one a hash's
     high 32 bits and its name's place + 1, 0 for none; the seed of that table's hash. *)
  let keys = fresh_ty m (St [ S (nn vals), false; S (nl i64s), false; S I64, false ]) in
  (* mine: no other map holds these keys, so a new name goes in their free room. *)
  let map = owned (St [ S I32, true; S (nn keys), true; S (nn vals), true; S I32, true; S I32, true ]) in
  (* A map of a literal whose keys and kinds the compiler knows, its values typed: this base, its ownership and keys,
     then a field each, of the type the compiler made for those keys (Aot.shape_type). *)
  let smap = Wasm.sub_ty m ~final:false [ own ] (St [ S I32, true; S (nn keys), false ]) in
  (* A shape: the name of its struct, its fields, and how a message names it, "an Ok". *)
  let shape = fresh_ty m (St [ S (nn bytes), false; S (nn vals), false; S (nn bytes), false ]) in
  let recd = owned (St [ S I32, true; S (nn shape), false; S (nn vals), true ]) in
  let fn = fresh_ty m (St [ S (Ref (false, Func)), false; S I32, false; S I32, false; S (nn bytes), false; S (nl vals), false ]) in
  let buf = fresh_ty m (St [ S (nn bytes), true; S I32, true ]) in
  (* What a read of a field remembers: the keys or shape it last met, and the place of the field there. *)
  let cache = fresh_ty m (St [ S (Ref (true, Eq)), true; S I32, true ]) in
  let i32s = fresh_ty m (Ar (S I32, true)) in
  (* A fiber: its parks, cancel, timer's mark, depth and call sites when parked, task, and the site that spawned it. *)
  let fib = fresh_ty m (St [ S I32, true; S I32, true; S I32, true; S I32, true; S (nl i32s), true; S v, true; S I32, false ]) in
  (* A wake: the fiber and the count of its park. *)
  let tok = fresh_ty m (St [ S (nn fib), false; S I32, false ]) in
  (* A queue: a ring of values, its first and its count. *)
  let q = fresh_ty m (St [ S (nn vals), true; S I32, true; S I32, true ]) in
  (* A channel: its values, size, receivers, senders, whether closed, and its number. *)
  let chan = fresh_ty m (St [ S (nn q), false; S I32, false; S (nn q), false; S (nn q), false; S I32, true; S I32, false ]) in
  (* A sender that waits on a full channel: its value, its wake, and whether a receiver took it. *)
  let sender = fresh_ty m (St [ S v, false; S (nn tok), false; S I32, true ]) in
  (* A task: whether done, its result, the wakes of those who wait for it, its fiber while it runs, its number. *)
  let task = fresh_ty m (St [ S I32, true; S v, true; S (nn q), false; S (nl fib), true; S I32, false ]) in
  { m; bytes; vals; f64s; i64s; boxi; boxf; atom; own; list; keys; map; smap; shape; recd; fn; buf; cache; i32s; fib; tok; q; chan;
    sender; task; fns = Hashtbl.create 8; texts = Hashtbl.create 64; inits = [] }

(* Fields. *)
let l_owned = 0
let l_rows = 1
let l_cols = 2
let l_store = 3
let l_tip = 4
let m_owned = 0
let m_keys = 1
let m_vals = 2
let m_count = 3
let m_mine = 4
let k_names = 0
let k_slots = 1
let k_seed = 2
let s_owned = 0
let s_keys = 1
let r_owned = 0
let r_shape = 1
let r_fields = 2
let f_code = 0
let f_arity = 1
let f_min = 2
let f_name = 3
let f_env = 4

(* Instructions. *)
let unreachable = Op 0x00
let drop = Op 0x1a
let select = Op 0x1b
let ret = Op 0x0f
let i32_eqz = Op 0x45
let i32_eq = Op 0x46
let i32_ne = Op 0x47
let i32_lt_s = Op 0x48
let i32_lt_u = Op 0x49
let i32_gt_s = Op 0x4a
let i32_gt_u = Op 0x4b
let i32_le_s = Op 0x4c
let i32_le_u = Op 0x4d
let i32_ge_s = Op 0x4e
let i32_ge_u = Op 0x4f
let i64_eqz = Op 0x50
let i64_eq = Op 0x51
let i64_ne = Op 0x52
let i64_lt_s = Op 0x53
let i64_lt_u = Op 0x54
let i64_gt_s = Op 0x55
let i64_gt_u = Op 0x56
let i64_le_s = Op 0x57
let i64_ge_s = Op 0x59
let i64_ge_u = Op 0x5a
let f64_eq = Op 0x61
let f64_ne = Op 0x62
let f64_lt = Op 0x63
let f64_gt = Op 0x64
let f64_le = Op 0x65
let f64_ge = Op 0x66
let i32_add = Op 0x6a
let i32_sub = Op 0x6b
let i32_mul = Op 0x6c
let i32_and = Op 0x71
let i32_or = Op 0x72
let i32_xor = Op 0x73
let i64_add = Op 0x7c
let i64_sub = Op 0x7d
let i64_mul = Op 0x7e
let i64_div_s = Op 0x7f
let i64_div_u = Op 0x80
let i64_rem_s = Op 0x81
let i64_rem_u = Op 0x82
let i64_and = Op 0x83
let i64_or = Op 0x84
let i64_xor = Op 0x85
let i64_shl = Op 0x86
let i64_shr_s = Op 0x87
let i64_shr_u = Op 0x88
let f64_abs = Op 0x99
let f64_neg = Op 0x9a
let f64_ceil = Op 0x9b
let f64_floor = Op 0x9c
let f64_trunc = Op 0x9d
let f64_sqrt = Op 0x9f
let f64_copysign = Op 0xa6
let f64_add = Op 0xa0
let f64_sub = Op 0xa1
let f64_mul = Op 0xa2
let f64_div = Op 0xa3
let i32_wrap = Op 0xa7
let i64_extend_s = Op 0xac
let i64_extend_u = Op 0xad
let f64_of_i32 = Op 0xb7
let f64_of_i64 = Op 0xb9
let i64_trunc_sat = Fc (6, [])
let ref_is_null = Op 0xd1
let ref_eq = Op 0xd3
let as_non_null = Op 0xd4
let struct_new t = Gc (0, [ t ])
let struct_get t f = Gc (2, [ t; f ])
let struct_set t f = Gc (5, [ t; f ])
let array_new t = Gc (6, [ t ])
let array_new_default t = Gc (7, [ t ])
let array_new_fixed t n = Gc (8, [ t; n ])
let array_get t = Gc (11, [ t ])
let array_get_u t = Gc (13, [ t ])
let array_set t = Gc (14, [ t ])
let array_len = Gc (15, [])
let array_copy t u = Gc (17, [ t; u ])
let ref_i31 = Gc (28, [])
let i31_get_s = Gc (29, [])
let load8 off = Mem (0x2d, 0, off)
let store8 off = Mem (0x3a, 0, off)
let load32 off = Mem (0x28, 2, off)
let store32 off = Mem (0x36, 2, off)
let i64 n = I64 (Int64.of_int n)

(* A loop over [i] from 0 below [n], both locals. *)
let upto i n body = [ I32 0; Lset i; Block (Bnone, [ Loop (Bnone, [ Lget i; Lget n; i32_ge_u; Br_if 1 ] @ body @ [ Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]) ]

(* A function being written: its locals. *)
type fb = { f : Wasm.func; mutable n : int; mutable rev : vt list; mutable tmp : int }

let local fb t =
  let i = List.length fb.f.params + fb.n in
  fb.n <- fb.n + 1;
  fb.rev <- t :: fb.rev;
  i

(* The runtime's functions: of the types, the parameters, results and the body, made at the first use. *)
let defs : (string, t -> vt list * vt list * (fb -> ins list)) Hashtbl.t = Hashtbl.create 128

let def name f = Hashtbl.replace defs name f

let need rt name =
  if not (Wasm.has_func rt.m name) then begin
    match Hashtbl.find_opt defs name with
    | Some d ->
      let ps, rs, body = d rt in
      let f = Wasm.func rt.m name ps rs in
      let fb = { f; n = 0; rev = []; tmp = -1 } in
      f.body <- body fb;
      f.locals <- List.rev fb.rev
    | None -> failwith ("no runtime function " ^ name)
  end;
  name

let call rt name = Call (need rt name)

(* Imports from the loader, and from JavaScript's Math. *)
let host rt name =
  let js = "js:" ^ name in
  (match name with
   | "write" -> import rt.m js "rt" "write" [ I32; I32; I32 ] []
   | "fail" -> import rt.m js "rt" "fail" [ I32; I32; I32 ] []
   | "ftoa" -> import rt.m js "rt" "ftoa" [ F64 ] [ I32 ]
   | "checkpoint" -> import rt.m js "rt" "checkpoint" [ I32 ] [ I32 ]
   | "rand32" -> import rt.m js "rt" "rand32" [] [ I32 ]
   | "now" -> import rt.m js "rt" "now" [] [ F64 ]
   | "number" -> import rt.m js "rt" "number" [ I32 ] [ F64 ]
   | "decimals" -> import rt.m js "rt" "decimals" [ F64; I32 ] [ I32 ]
   | "park" -> import rt.m js "rt" "park" [ nn rt.fib; I32 ] [ I32 ]
   | "wake" -> import rt.m js "rt" "wake" [ nn rt.fib ] []
   | "spawn" -> import rt.m js "rt" "spawn" [ nn rt.fib; nn rt.fn; I32 ] []
   | "timer" -> import rt.m js "rt" "timer" [ nn rt.fib; F64 ] [ I32 ]
   | "untimer" -> import rt.m js "rt" "untimer" [ I32 ] []
   | "unwind" -> import rt.m js "rt" "unwind" [] []
   | "first" -> import rt.m js "rt" "first" [ nn rt.fib ] []
   | "pow" -> import rt.m js "Math" "pow" [ F64; F64 ] [ F64 ]
   | f -> import rt.m js "Math" f [ F64 ] [ F64 ]);
  Call js

let gl rt name t mut init =
  Wasm.global rt.m name t mut init;
  name

let g_true rt = Gget (gl rt "true" (nn rt.atom) false [ I32 1; struct_new rt.atom ])
let g_false rt = Gget (gl rt "false" (nn rt.atom) false [ I32 0; struct_new rt.atom ])
let g_undef rt = Gget (gl rt "undef" (nn rt.atom) false [ I32 2; struct_new rt.atom ])
let outn rt = gl rt "outn" I32 true [ I32 0 ]
let depth rt = gl rt "depth" I32 true [ I32 0 ]
let fuel rt = gl rt "fuel" I64 true [ i64 fuel_period ]
let missing = Rnull None_

(* A text in a constant, as the keys of a literal: a global made of its bytes, about 3 bytes a byte. *)
let const_text rt s =
  let key = "\000" ^ s in
  match Hashtbl.find_opt rt.texts key with
  | Some g -> Gget g
  | None ->
    let g = "t" ^ string_of_int (Hashtbl.length rt.texts) in
    Hashtbl.replace rt.texts key g;
    let n = String.length s in
    Wasm.global rt.m g (nn rt.bytes) false (List.init n (fun i -> I32 (Char.code s.[i])) @ [ array_new_fixed rt.bytes n ]);
    Gget g

(* A text in code: from 8 bytes, its bytes in a data segment, a byte each, made at the start into a global that holds an
   empty text until then; a shorter one a constant. *)
let text rt s =
  if String.length s < 8 then const_text rt s
  else
    match Hashtbl.find_opt rt.texts s with
    | Some g -> Gget g
    | None ->
      let g = "t" ^ string_of_int (Hashtbl.length rt.texts) in
      Hashtbl.replace rt.texts s g;
      Wasm.global rt.m g (nn rt.bytes) true [ array_new_fixed rt.bytes 0 ];
      rt.inits <- rt.inits @ [ I32 0; I32 (String.length s); Gcd (9, rt.bytes, Wasm.data rt.m s); Gset g ];
      Gget g

let bool_of rt = [ If (Bval v, [ g_true rt ], [ g_false rt ]) ]

(* The type of the code of a function value of n arguments: the function value itself, then the arguments. *)
let fn_type rt n =
  match Hashtbl.find_opt rt.fns n with
  | Some t -> t
  | None ->
    let t = Wasm.fn_ty rt.m (nn rt.fn :: List.init n (fun _ -> v)) [ v ] in
    Hashtbl.replace rt.fns n t;
    t

(* Numbers. *)

let fits63 r = [ Lget r; i64 1; i64_shl; i64 1; i64_shr_s; Lget r; i64_eq ]

let () =
  def "box_i" (fun rt -> [ I64 ], [ v ], fun _ ->
      [ Lget 0; i64 (1 lsl 30); i64_add; i64 (1 lsl 31); i64_lt_u;
        If (Bval v, [ Lget 0; i32_wrap; ref_i31 ], [ Lget 0; struct_new rt.boxi ]) ]);
  def "box_f" (fun rt -> [ F64 ], [ v ], fun _ -> [ Lget 0; struct_new rt.boxf ]);
  (* The integer of a value that is one. *)
  def "int_of" (fun rt -> [ v ], [ I64 ], fun _ ->
      [ Block (Bval (Ref (false, I31)),
               [ Lget 0; Br_on_cast (0, true, Eq, false, I31); Cast (false, T rt.boxi); struct_get rt.boxi 0; ret ]);
        i31_get_s; i64_extend_s ]);
  def "float_of" (fun rt -> [ v ], [ F64 ], fun _ -> [ Lget 0; Cast (false, T rt.boxf); struct_get rt.boxf 0 ]);
  def "is_int" (fun rt -> [ v ], [ I32 ], fun _ -> [ Lget 0; Test (false, I31); Lget 0; Test (false, T rt.boxi); i32_or ]);
  (* The kind of an operand of arithmetic, a boolean counting as an integer: 0 an integer, 1 a float, 2 missing, 3 an
     array, 4 anything else. *)
  def "kind" (fun rt -> [ v ], [ I32 ], fun _ ->
      [ Lget 0; ref_is_null; If (Bnone, [ I32 2; ret ], []);
        Lget 0; call rt "is_int"; Lget 0; g_true rt; ref_eq; i32_or; Lget 0; g_false rt; ref_eq; i32_or; If (Bnone, [ I32 0; ret ], []);
        Lget 0; Test (false, T rt.boxf); If (Bnone, [ I32 1; ret ], []);
        Lget 0; Test (false, T rt.list); If (Bval I32, [ I32 3 ], [ I32 4 ]) ]);
  def "as_int" (fun rt -> [ v ], [ I64 ], fun _ ->
      [ Lget 0; g_true rt; ref_eq; If (Bnone, [ i64 1; ret ], []);
        Lget 0; g_false rt; ref_eq; If (Bnone, [ i64 0; ret ], []);
        Lget 0; call rt "int_of" ]);
  def "as_float" (fun rt -> [ v ], [ F64 ], fun _ ->
      [ Lget 0; Test (false, T rt.boxf); If (Bval F64, [ Lget 0; call rt "float_of" ], [ Lget 0; call rt "as_int"; f64_of_i64 ]) ]);
  (* Trie.int_float: an integer against a float, exactly: -1, 0, 1, or 2 for NaN. *)
  def "int_float" (fun _ -> [ I64; F64 ], [ I32 ], fun fb ->
      let f = local fb F64 in
      [ Lget 0; f64_of_i64; Lset f;
        Lget f; Lget 1; f64_lt; If (Bnone, [ I32 (-1); ret ], []);
        Lget f; Lget 1; f64_gt; If (Bnone, [ I32 1; ret ], []);
        Lget f; Lget 1; f64_ne; If (Bnone, [ I32 2; ret ], []);
        Lget 1; F64 0x1p62; f64_ge; If (Bnone, [ I32 (-1); ret ], []);
        Lget 0; Lget 1; i64_trunc_sat; i64_gt_s; Lget 0; Lget 1; i64_trunc_sat; i64_lt_s; i32_sub ])

(* Texts being built: a buffer of bytes and their count. *)
let () =
  def "buf_new" (fun rt -> [], [ nn rt.buf ], fun _ -> [ I32 32; array_new_default rt.bytes; I32 0; struct_new rt.buf ]);
  def "buf_room" (fun rt -> [ nn rt.buf; I32 ], [], fun fb ->
      let nb = local fb (nn rt.bytes) and cap = local fb I32 in
      [ Lget 0; struct_get rt.buf 1; Lget 1; i32_add; Lget 0; struct_get rt.buf 0; array_len; i32_gt_u;
        If (Bnone, [
            Lget 0; struct_get rt.buf 0; array_len; I32 2; i32_mul; Lset cap;
            Lget cap; Lget 0; struct_get rt.buf 1; Lget 1; i32_add; i32_lt_u;
            If (Bnone, [ Lget 0; struct_get rt.buf 1; Lget 1; i32_add; Lset cap ], []);
            Lget cap; array_new_default rt.bytes; Lset nb;
            Lget nb; I32 0; Lget 0; struct_get rt.buf 0; I32 0; Lget 0; struct_get rt.buf 1; array_copy rt.bytes rt.bytes;
            Lget 0; Lget nb; struct_set rt.buf 0 ], []) ]);
  def "buf_byte" (fun rt -> [ nn rt.buf; I32 ], [], fun _ ->
      [ Lget 0; I32 1; call rt "buf_room";
        Lget 0; struct_get rt.buf 0; Lget 0; struct_get rt.buf 1; Lget 1; array_set rt.bytes;
        Lget 0; Lget 0; struct_get rt.buf 1; I32 1; i32_add; struct_set rt.buf 1 ]);
  def "buf_add" (fun rt -> [ nn rt.buf; nn rt.bytes ], [], fun _ ->
      [ Lget 0; Lget 1; array_len; call rt "buf_room";
        Lget 0; struct_get rt.buf 0; Lget 0; struct_get rt.buf 1; Lget 1; I32 0; Lget 1; array_len; array_copy rt.bytes rt.bytes;
        Lget 0; Lget 0; struct_get rt.buf 1; Lget 1; array_len; i32_add; struct_set rt.buf 1 ]);
  (* [len] bytes of the memory from [ptr]. *)
  def "buf_mem" (fun rt -> [ nn rt.buf; I32; I32 ], [], fun fb ->
      let i = local fb I32 in
      [ Lget 0; Lget 2; call rt "buf_room" ]
      @ upto i 2 [ Lget 0; struct_get rt.buf 0; Lget 0; struct_get rt.buf 1; Lget i; i32_add; Lget 1; Lget i; i32_add; load8 0; array_set rt.bytes ]
      @ [ Lget 0; Lget 0; struct_get rt.buf 1; Lget 2; i32_add; struct_set rt.buf 1 ]);
  def "buf_done" (fun rt -> [ nn rt.buf ], [ nn rt.bytes ], fun fb ->
      let r = local fb (nn rt.bytes) in
      [ Lget 0; struct_get rt.buf 1; array_new_default rt.bytes; Lset r;
        Lget r; I32 0; Lget 0; struct_get rt.buf 0; I32 0; Lget 0; struct_get rt.buf 1; array_copy rt.bytes rt.bytes; Lget r ])

(* Output, through the memory. *)
let () =
  def "flush" (fun rt -> [], [], fun _ ->
      [ Gget (outn rt); If (Bnone, [ I32 0; Gget (outn rt); I32 1; host rt "write"; I32 0; Gset (outn rt) ], []) ]);
  def "out_byte" (fun rt -> [ I32 ], [], fun _ ->
      [ Gget (outn rt); I32 out_cap; i32_ge_u; If (Bnone, [ call rt "flush" ], []);
        Gget (outn rt); Lget 0; store8 0; Gget (outn rt); I32 1; i32_add; Gset (outn rt) ]);
  def "out_mem" (fun rt -> [ I32; I32 ], [], fun fb ->
      let i = local fb I32 in
      upto i 1 [ Lget 0; Lget i; i32_add; load8 0; call rt "out_byte" ]);
  def "out_bytes" (fun rt -> [ nn rt.bytes ], [], fun fb ->
      let i = local fb I32 and n = local fb I32 in
      [ Lget 0; array_len; Lset n ]
      @ upto i n [ Gget (outn rt); I32 out_cap; i32_ge_u; If (Bnone, [ call rt "flush" ], []);
                   Gget (outn rt); Lget 0; Lget i; array_get_u rt.bytes; store8 0; Gget (outn rt); I32 1; i32_add; Gset (outn rt) ]);
  (* The digits of an integer in the scratch area: where they start; they end at [scratch] + 40. *)
  def "digits" (fun _ -> [ I64 ], [ I32 ], fun fb ->
      let p = local fb I32 and u = local fb I64 in
      [ I32 (scratch + 40); Lset p;
        Lget 0; i64 0; i64_lt_s; If (Bval I64, [ i64 0; Lget 0; i64_sub ], [ Lget 0 ]); Lset u;
        Loop (Bnone, [
            Lget p; I32 1; i32_sub; Lset p;
            Lget p; Lget u; i64 10; i64_rem_u; i32_wrap; I32 48; i32_add; store8 0;
            Lget u; i64 10; i64_div_u; Lset u;
            Lget u; i64 0; i64_ne; Br_if 0 ]);
        Lget 0; i64 0; i64_lt_s; If (Bnone, [ Lget p; I32 1; i32_sub; Lset p; Lget p; I32 45; store8 0 ], []);
        Lget p ]);
  def "write_int" (fun rt -> [ nn rt.buf; I64 ], [], fun fb ->
      let p = local fb I32 in
      [ Lget 1; call rt "digits"; Lset p; Lget 0; Lget p; I32 (scratch + 40); Lget p; i32_sub; call rt "buf_mem" ]);
  def "write_float" (fun rt -> [ nn rt.buf; F64 ], [], fun _ -> [ Lget 0; I32 scratch; Lget 1; host rt "ftoa"; call rt "buf_mem" ]);
  def "itoa" (fun rt -> [ I64 ], [ nn rt.bytes ], fun fb ->
      let x = local fb (nn rt.buf) in
      [ call rt "buf_new"; Lset x; Lget x; Lget 0; call rt "write_int"; Lget x; call rt "buf_done" ]);
  def "ftoa" (fun rt -> [ F64 ], [ nn rt.bytes ], fun fb ->
      let x = local fb (nn rt.buf) in
      [ call rt "buf_new"; Lset x; Lget x; Lget 0; call rt "write_float"; Lget x; call rt "buf_done" ]);
  (* Print's one value: a text raw, a number without a text in between. *)
  def "print" (fun rt -> [ v ], [], fun fb ->
      let p = local fb I32 in
      [ Lget 0; Test (false, T rt.bytes); If (Bnone, [ Lget 0; Cast (false, T rt.bytes); call rt "out_bytes"; ret ], []);
        Lget 0; call rt "is_int";
        If (Bnone, [ Lget 0; call rt "int_of"; call rt "digits"; Lset p; Lget p; I32 (scratch + 40); Lget p; i32_sub; call rt "out_mem"; ret ], []);
        Lget 0; call rt "text_of"; call rt "out_bytes" ]);
  def "print_i" (fun rt -> [ I64 ], [], fun fb ->
      let p = local fb I32 in
      [ Lget 0; call rt "digits"; Lset p; Lget p; I32 (scratch + 40); Lget p; i32_sub; call rt "out_mem" ]);
  def "print_f" (fun rt -> [ F64 ], [], fun _ -> [ I32 scratch; Lget 0; host rt "ftoa"; call rt "out_mem" ])

(* Typed maps, the work of the compiler's types done at the end of a build (Aot.finish): [sget] the value of field k,
   [sto_map] the same map in the general form, [scopy] an owned copy; their values held twice then. [as_map] turns a typed
   map into the general form, for what reads a map whole: Print, ==, a pattern. *)
let () =
  def "sget" (fun rt -> [ nn rt.smap; I32 ], [ v ], fun _ -> [ unreachable ]);
  def "sto_map" (fun rt -> [ nn rt.smap ], [ nn rt.map ], fun _ -> [ unreachable ]);
  def "scopy" (fun rt -> [ nn rt.smap ], [ nn rt.smap ], fun _ -> [ unreachable ]);
  def "as_map" (fun rt -> [ v ], [ v ], fun _ ->
      [ Lget 0; Test (false, T rt.smap); If (Bval v, [ Lget 0; Cast (false, T rt.smap); call rt "sto_map" ], [ Lget 0 ]) ])

(* Element k, from 0, of a list, as a value. *)
let () =
  def "elem" (fun rt -> [ nn rt.list; I32 ], [ v ], fun _ ->
      [ Block (Bval (nn rt.f64s), [
            Block (Bval (nn rt.i64s), [
                Lget 0; struct_get rt.list l_store;
                Br_on_cast (0, false, Array, false, T rt.i64s);
                Br_on_cast (1, false, Array, false, T rt.f64s);
                Cast (false, T rt.vals); Lget 1; array_get rt.vals; ret ]);
            Lget 1; array_get rt.i64s; call rt "box_i"; ret ]);
        Lget 1; array_get rt.f64s; call rt "box_f" ])

(* Writes a value in a buffer: as code, a text in quotes, when [code] is 1; else a text raw. *)
let () =
  def "write_quoted" (fun rt -> [ nn rt.buf; nn rt.bytes ], [], fun fb ->
      let i = local fb I32 and c = local fb I32 and n = local fb I32 in
      [ Lget 1; array_len; Lset n; Lget 0; I32 34; call rt "buf_byte" ]
      @ upto i n [ Lget 1; Lget i; array_get_u rt.bytes; Lset c;
                   Lget c; I32 34; i32_eq; Lget c; I32 92; i32_eq; i32_or; If (Bnone, [ Lget 0; I32 92; call rt "buf_byte" ], []);
                   Lget 0; Lget c; call rt "buf_byte" ]
      @ [ Lget 0; I32 34; call rt "buf_byte" ]);
  def "write" (fun rt -> [ nn rt.buf; v; I32 ], [], fun fb ->
      let add s = [ Lget 0; text rt s; call rt "buf_add" ] in
      let byte c = [ Lget 0; I32 (Char.code c); call rt "buf_byte" ] in
      let k = local fb I32 and n = local fb I32 and r = local fb I32 and j = local fb I32 and num = local fb I32 in
      let lst = local fb (nl rt.list) and mp = local fb (nl rt.map) and rc = local fb (nl rt.recd) and vs = local fb (nl rt.vals) in
      let sep c = [ Lget k; If (Bnone, byte c @ byte ' ', []) ] in
      let sub e = [ Lget 0 ] @ e @ [ I32 1; call rt "write" ] in
      let x = 1 in
      [ Lget x; ref_is_null; If (Bnone, add "missing" @ [ ret ], []);
        Lget x; Test (false, T rt.smap); If (Bnone, [ Lget x; call rt "as_map"; Lset x ], []);
        Lget x; call rt "is_int"; If (Bnone, [ Lget 0; Lget x; call rt "int_of"; call rt "write_int"; ret ], []);
        Lget x; Test (false, T rt.boxf); If (Bnone, [ Lget 0; Lget x; call rt "float_of"; call rt "write_float"; ret ], []);
        Lget x; g_true rt; ref_eq; If (Bnone, add "true" @ [ ret ], []);
        Lget x; g_false rt; ref_eq; If (Bnone, add "false" @ [ ret ], []);
        Lget x; Test (false, T rt.bytes);
        If (Bnone, [ Lget 2; If (Bnone, [ Lget 0; Lget x; Cast (false, T rt.bytes); call rt "write_quoted" ],
                                 [ Lget 0; Lget x; Cast (false, T rt.bytes); call rt "buf_add" ]); ret ], []);
        Lget x; Test (false, T rt.list);
        If (Bnone,
            [ Lget x; Cast (false, T rt.list); Lset lst;
              Lget lst; struct_get rt.list l_rows; Lset r;
              Lget lst; struct_get rt.list l_rows; Lget lst; struct_get rt.list l_cols; i32_mul; Lset n;
              Lget n; i32_eqz; If (Bnone, add "[]" @ [ ret ], []) ]
            @ byte '['
            @ [ Lget r; I32 1; i32_eq; Lget lst; struct_get rt.list l_cols; I32 1; i32_eq; i32_or;
                If (Bnone,
                    upto k n ([ Lget k; If (Bnone, [ Lget 0; Lget r; I32 1; i32_eq; If (Bval I32, [ I32 44 ], [ I32 59 ]); call rt "buf_byte" ] @ byte ' ', []) ]
                              @ sub [ Lget lst; as_non_null; Lget k; call rt "elem" ]),
                    (* A matrix: its rows, the columns of numbers apart by a space, else by a comma. *)
                    [ I32 1; Lset num ]
                    @ upto k n [ Lget lst; as_non_null; Lget k; call rt "elem"; call rt "kind"; I32 1; i32_gt_u; If (Bnone, [ I32 0; Lset num ], []) ]
                    @ upto k r (sep ';'
                                @ [ Lget lst; struct_get rt.list l_cols; Lset n ]
                                @ upto j n ([ Lget j; If (Bnone, [ Lget num; If (Bnone, byte ' ', byte ',' @ byte ' ') ], []) ]
                                            @ sub [ Lget lst; as_non_null; Lget j; Lget r; i32_mul; Lget k; i32_add; call rt "elem" ]))) ]
            @ byte ']' @ [ ret ], []);
        Lget x; Test (false, T rt.map);
        If (Bnone,
            [ Lget x; Cast (false, T rt.map); Lset mp; Lget mp; struct_get rt.map m_vals; Lset vs; Lget mp; struct_get rt.map m_count; Lset n ]
            @ byte '{'
            @ upto k n (sep ','
                        @ [ Lget 0; Lget mp; struct_get rt.map m_keys; struct_get rt.keys k_names; Lget k; array_get rt.vals; I32 0; call rt "write" ]
                        @ byte ':' @ byte ' '
                        @ sub [ Lget vs; Lget k; array_get rt.vals ])
            @ byte '}' @ [ ret ], []);
        Lget x; Test (false, T rt.recd);
        If (Bnone,
            [ Lget x; Cast (false, T rt.recd); Lset rc;
              Lget rc; struct_get rt.recd r_fields; Lset vs; Lget vs; as_non_null; array_len; Lset n;
              Lget 0; Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 0; call rt "buf_add" ]
            @ byte '('
            @ [ Lget n; I32 1; i32_eq; Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 0; array_len; I32 0; i32_ne; i32_and;
                If (Bnone, sub [ Lget vs; I32 0; array_get rt.vals ],
                    upto k n (sep ','
                              @ [ Lget 0; Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 1; Lget k; array_get rt.vals;
                                  Cast (false, T rt.bytes); call rt "buf_add" ]
                              @ add " = "
                              @ sub [ Lget vs; Lget k; array_get rt.vals ])) ]
            @ byte ')' @ [ ret ], []);
        Lget x; Test (false, T rt.fn);
        If (Bnone, add "function " @ [ Lget 0; Lget x; Cast (false, T rt.fn); struct_get rt.fn f_name; call rt "buf_add"; ret ], []);
        (* A channel or a task as the interpreter shows a handle: <channel 3>. *)
        Lget x; Test (false, T rt.chan);
        If (Bnone, add "<channel " @ [ Lget 0; Lget x; Cast (false, T rt.chan); struct_get rt.chan 5; i64_extend_u; call rt "write_int" ] @ byte '>' @ [ ret ], []);
        Lget x; Test (false, T rt.task);
        If (Bnone, add "<task " @ [ Lget 0; Lget x; Cast (false, T rt.task); struct_get rt.task 4; i64_extend_u; call rt "write_int" ] @ byte '>' @ [ ret ], []) ]
      @ add "undefined");
  def "show" (fun rt -> [ v ], [ nn rt.bytes ], fun fb ->
      let x = local fb (nn rt.buf) in
      [ call rt "buf_new"; Lset x; Lget x; Lget 0; I32 1; call rt "write"; Lget x; call rt "buf_done" ]);
  def "text_of" (fun rt -> [ v ], [ nn rt.bytes ], fun _ ->
      [ Block (Bval (nn rt.bytes), [ Lget 0; Br_on_cast (0, true, Eq, false, T rt.bytes); call rt "show"; ret ]) ]);
  (* How a message names a value: Value.describe. *)
  def "describe" (fun rt -> [ v ], [ nn rt.bytes ], fun fb ->
      let x = local fb (nn rt.buf) in
      (* A number or a text as write gives them, by the writers of each alone: a message needs no printer of arrays. *)
      let shown pre value = [ call rt "buf_new"; Lset x; Lget x; text rt pre; call rt "buf_add"; Lget x ] @ value @ [ Lget x; call rt "buf_done"; ret ] in
      [ Lget 0; ref_is_null; If (Bnone, [ text rt "missing"; ret ], []);
        Lget 0; g_true rt; ref_eq; If (Bnone, [ text rt "true"; ret ], []);
        Lget 0; g_false rt; ref_eq; If (Bnone, [ text rt "false"; ret ], []);
        Lget 0; call rt "is_int"; If (Bnone, shown "the number " [ Lget 0; call rt "int_of"; call rt "write_int" ], []);
        Lget 0; Test (false, T rt.boxf); If (Bnone, shown "the number " [ Lget 0; call rt "float_of"; call rt "write_float" ], []);
        Lget 0; Test (false, T rt.bytes); If (Bnone, shown "the text " [ Lget 0; Cast (false, T rt.bytes); call rt "write_quoted" ], []);
        Lget 0; Test (false, T rt.list); If (Bnone, [ text rt "an array"; ret ], []);
        Lget 0; Test (false, T rt.map); Lget 0; Test (false, T rt.smap); i32_or; If (Bnone, [ text rt "a dictionary"; ret ], []);
        Lget 0; Test (false, T rt.recd); If (Bnone, [ Lget 0; Cast (false, T rt.recd); struct_get rt.recd r_shape; struct_get rt.shape 2; ret ], []);
        Lget 0; Test (false, T rt.fn);
        If (Bnone, [ call rt "buf_new"; Lset x; Lget x; text rt "function "; call rt "buf_add";
                     Lget x; Lget 0; Cast (false, T rt.fn); struct_get rt.fn f_name; call rt "buf_add"; Lget x; call rt "buf_done"; ret ], []);
        Lget 0; Test (false, T rt.chan); If (Bnone, [ text rt "a channel"; ret ], []);
        Lget 0; Test (false, T rt.task); If (Bnone, [ text rt "a task"; ret ], []);
        text rt "an undefined value" ])

(* Errors. *)
let () =
  (* A text to the loader, on a stream: through the memory, by pieces. *)
  def "send" (fun rt -> [ nn rt.bytes; I32 ], [], fun fb ->
      let i = local fb I32 and k = local fb I32 in
      [ Block (Bnone, [ Loop (Bnone, [
            Lget i; Lget 0; array_len; i32_ge_u; Br_if 1;
            I32 0; Lset k;
            Block (Bnone, [ Loop (Bnone, [
                Lget k; I32 out_cap; i32_ge_u; Br_if 1; Lget i; Lget 0; array_len; i32_ge_u; Br_if 1;
                Lget k; Lget 0; Lget i; array_get_u rt.bytes; store8 0;
                Lget k; I32 1; i32_add; Lset k; Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
            I32 0; Lget k; Lget 1; host rt "write"; Br 0 ]) ]) ]);
  (* The message [t] with the texts [a] and [b] for its \001 and \002, the hint [h], at [site]. *)
  def "fail" (fun rt -> [ nn rt.bytes; nl rt.bytes; nl rt.bytes; nl rt.bytes; I32; I32 ], [], fun fb ->
      let x = local fb (nn rt.buf) and i = local fb I32 and c = local fb I32 and n = local fb I32 in
      [ call rt "flush"; call rt "buf_new"; Lset x; Lget 0; array_len; Lset n ]
      @ upto i n [ Lget 0; Lget i; array_get_u rt.bytes; Lset c;
                   Lget c; I32 1; i32_eq;
                   If (Bnone, [ Lget x; Lget 2; as_non_null; call rt "buf_add" ],
                       [ Lget c; I32 2; i32_eq;
                         If (Bnone, [ Lget x; Lget 3; as_non_null; call rt "buf_add" ], [ Lget x; Lget c; call rt "buf_byte" ]) ]) ]
      @ [ Lget x; call rt "buf_done"; I32 3; call rt "send";
          Lget 1; ref_is_null; If (Bnone, [], [ Lget 1; as_non_null; I32 4; call rt "send" ]);
          Lget 5; Gget (depth rt); Lget 4; host rt "fail"; unreachable ])

(* The kinds of errors, as the interpreter names them (Value.kind_name), by their number for the loader. *)
let k_type = 2
let k_index = 3
let k_field = 4
let k_math = 5
let k_user = 7

(* Fails with a message of Messages made with "\001" and "\002" for its operands, which [operands] puts on the stack as
   texts, at the site [site] puts there; [kind] is the error's, which a fiber's task holds. *)
let fail ?(kind = k_type) rt (m : Messages.t) operands site =
  let ops =
    match operands with
    | [] -> [ Rnull (T rt.bytes); Rnull (T rt.bytes) ]
    | [ a ] -> a @ [ Rnull (T rt.bytes) ]
    | [ a; b ] -> a @ b
    | _ -> invalid_arg "Rt.fail"
  in
  [ text rt m.text; (match m.hint with Some h -> text rt h | None -> Rnull (T rt.bytes)) ] @ ops @ [ I32 kind ] @ site @ [ call rt "fail"; unreachable ]

let a1 = "\001"
let a2 = "\002"

(* Integers, checked as the interpreter checks them. *)
let () =
  let ovf rt op site = fail ~kind:k_math rt (Messages.overflow a1 op a2) [ [ Lget 0; call rt "itoa" ]; [ Lget 1; call rt "itoa" ] ] [ Lget site ] in
  def "add_fail" (fun rt -> [ I64; I64; I32 ], [], fun _ -> ovf rt "+" 2);
  def "sub_fail" (fun rt -> [ I64; I64; I32 ], [], fun _ -> ovf rt "-" 2);
  def "add_i" (fun rt -> [ I64; I64; I32 ], [ I64 ], fun fb ->
      let r = local fb I64 in
      [ Lget 0; Lget 1; i64_add; Lset r ] @ fits63 r @ [ If (Bnone, [ Lget r; ret ], []) ] @ ovf rt "+" 2);
  def "sub_i" (fun rt -> [ I64; I64; I32 ], [ I64 ], fun fb ->
      let r = local fb I64 in
      [ Lget 0; Lget 1; i64_sub; Lset r ] @ fits63 r @ [ If (Bnone, [ Lget r; ret ], []) ] @ ovf rt "-" 2);
  def "mul_i" (fun rt -> [ I64; I64; I32 ], [ I64 ], fun fb ->
      let r = local fb I64 in
      (* Both within 2^31 - 1 of zero: below 2^62 in size, it fits; -2^31 squared is 2^62, one too many. *)
      let small x = [ Lget x; i64 ((1 lsl 31) - 1); i64_add; i64 ((1 lsl 32) - 1); i64_lt_u ] in
      small 0 @ small 1 @ [ i32_and; If (Bnone, [ Lget 0; Lget 1; i64_mul; ret ], []);
                            Lget 0; i64_eqz; Lget 1; i64_eqz; i32_or; If (Bnone, [ i64 0; ret ], []);
                            Lget 0; Lget 1; i64_mul; Lset r ]
      @ fits63 r @ [ If (Bnone, [ Lget r; Lget 1; i64_div_s; Lget 0; i64_eq; If (Bnone, [ Lget r; ret ], []) ], []) ]
      @ ovf rt "*" 2);
  def "neg_i" (fun rt -> [ I64; I32 ], [ I64 ], fun _ ->
      [ Lget 0; I64 (Int64.of_int min_int); i64_ne; If (Bnone, [ i64 0; Lget 0; i64_sub; ret ], []) ]
      @ fail ~kind:k_math rt (Messages.overflow_neg a1) [ [ Lget 0; call rt "itoa" ] ] [ Lget 1 ]);
  (* math.Div and math.Mod: rounded down. *)
  def "div_i" (fun rt -> [ I64; I64; I32 ], [ I64 ], fun fb ->
      let q = local fb I64 in
      [ Lget 1; i64_eqz; If (Bnone, fail ~kind:k_math rt (Messages.div_zero "Div") [] [ Lget 2 ], []);
        Lget 0; I64 (Int64.of_int min_int); i64_eq; Lget 1; i64 (-1); i64_eq; i32_and;
        If (Bnone, fail ~kind:k_math rt (Messages.overflow a1 "/" "-1") [ [ Lget 0; call rt "itoa" ] ] [ Lget 2 ], []);
        Lget 0; Lget 1; i64_div_s; Lset q;
        Lget 0; Lget 1; i64_rem_s; i64 0; i64_ne; Lget 0; i64 0; i64_lt_s; Lget 1; i64 0; i64_lt_s; i32_xor; i32_and;
        If (Bval I64, [ Lget q; i64 1; i64_sub ], [ Lget q ]) ]);
  def "mod_i" (fun rt -> [ I64; I64; I32 ], [ I64 ], fun fb ->
      let r = local fb I64 in
      [ Lget 1; i64_eqz; If (Bnone, fail ~kind:k_math rt (Messages.div_zero "Mod") [] [ Lget 2 ], []);
        Lget 0; Lget 1; i64_rem_s; Lset r;
        Lget r; i64 0; i64_ne; Lget r; i64 0; i64_lt_s; Lget 1; i64 0; i64_lt_s; i32_xor; i32_and;
        If (Bval I64, [ Lget r; Lget 1; i64_add ], [ Lget r ]) ]);
  (* Arith.int_pow: by squares, each product checked. *)
  def "pow_i" (fun rt -> [ I64; I64; I32 ], [ I64 ], fun fb ->
      let h = local fb I64 in
      [ Lget 1; i64_eqz; If (Bnone, [ i64 1; ret ], []);
        Lget 1; i64 1; i64_eq; If (Bnone, [ Lget 0; ret ], []);
        Lget 0; Lget 1; i64 2; i64_div_s; Lget 2; call rt "pow_i"; Lset h;
        Lget h; Lget h; Lget 2; call rt "mul_i"; Lset h;
        Lget 1; i64 1; Op 0x83; i64_eqz; If (Bval I64, [ Lget h ], [ Lget h; Lget 0; Lget 2; call rt "mul_i" ]) ])

(* A message of Messages whose operands aren't texts: these texts of it are replaced by the placeholders. *)
let replace text pairs =
  let one s (x, y) =
    let n = String.length x and b = Buffer.create (String.length s) in
    let i = ref 0 in
    while !i < String.length s do
      if !i + n <= String.length s && String.sub s !i n = x then (Buffer.add_string b y; i := !i + n)
      else (Buffer.add_char b s.[!i]; incr i)
    done;
    Buffer.contents b
  in
  List.fold_left one text pairs

let shape_msg =
  let m = Messages.shape [| 1000001; 1000002 |] [| 1000003; 1000004 |] in
  { m with text = replace m.text [ "1000001 by 1000002", a1; "1000003 by 1000004", a2 ] }

(* Arithmetic on values: op 0 add, 1 sub, 2 mul, 3 div, 4 pow, as Arith; an array takes each of its cells. *)
let verbs = [| "add", "and", false; "subtract", "from", true; "multiply", "by", false; "divide", "by", false; "raise", "to the power", false |]

let () =
  def "arith" (fun rt -> [ I32; v; v; I32 ], [ v ], fun fb ->
      let ka = local fb I32 and kb = local fb I32 and x = local fb F64 and y = local fb F64 in
      let a = 1 and b = 2 and site = 3 in
      let bad k =
        let verb, joiner, flipped = verbs.(k) in
        let texts text = Messages.binary verb a1 joiner a2 text in
        let ops = if flipped then [ [ Lget b; call rt "describe" ]; [ Lget a; call rt "describe" ] ] else [ [ Lget a; call rt "describe" ]; [ Lget b; call rt "describe" ] ] in
        [ Lget a; Test (false, T rt.bytes); Lget b; Test (false, T rt.bytes); i32_or;
          If (Bnone, fail rt (texts true) ops [ Lget site ], fail rt (texts false) ops [ Lget site ]) ]
      in
      let per_op f =
        [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Lget 0; Br_table ([ 0; 1; 2; 3 ], 4) ]) ] @ f 0) ] @ f 1) ] @ f 2) ] @ f 3) ] @ f 4
      in
      [ Lget a; call rt "kind"; Lset ka; Lget b; call rt "kind"; Lset kb;
        Lget ka; I32 3; i32_eq; Lget kb; I32 3; i32_eq; i32_or; If (Bnone, [ Lget 0; Lget a; Lget b; Lget site; call rt "broadcast:arith"; ret ], []);
        (* Two integers: checked; a division gives a float, a power of a negative exponent too. *)
        Lget ka; Lget kb; i32_or; i32_eqz;
        If (Bnone,
            per_op (fun k ->
                let int f = [ Lget a; call rt "as_int"; Lget b; call rt "as_int"; Lget site; call rt f; call rt "box_i"; ret ] in
                match k with
                | 0 -> int "add_i"
                | 1 -> int "sub_i"
                | 2 -> int "mul_i"
                | 3 -> [ Lget a; call rt "as_float"; Lget b; call rt "as_float"; f64_div; call rt "box_f"; ret ]
                | _ -> [ Lget b; call rt "as_int"; i64 0; i64_ge_s; If (Bnone, int "pow_i", []);
                         Lget a; call rt "as_float"; Lget b; call rt "as_float"; host rt "pow"; call rt "box_f"; ret ]), []);
        Lget ka; I32 1; i32_le_u; Lget kb; I32 1; i32_le_u; i32_and;
        If (Bnone,
            [ Lget a; call rt "as_float"; Lset x; Lget b; call rt "as_float"; Lset y ]
            @ per_op (fun k ->
                [ Lget x; Lget y; (match k with 0 -> f64_add | 1 -> f64_sub | 2 -> f64_mul | 3 -> f64_div | _ -> host rt "pow");
                  call rt "box_f"; ret ]), []);
        (* missing with numbers or missing. *)
        Lget ka; I32 2; i32_eq; Lget kb; I32 2; i32_le_u; i32_and; Lget kb; I32 2; i32_eq; Lget ka; I32 1; i32_le_u; i32_and; i32_or;
        If (Bnone, [ missing; ret ], []) ]
      @ per_op (fun k -> bad k) @ [ unreachable ]);
  (* An operation of two operands, one at least an array, cell by cell: a value of an array of the same sizes, or of a
     scalar. *)
  List.iter (fun (name, cellwise) -> def name (fun rt -> [ I32; v; v; I32 ], [ v ], fun fb ->
      let la = local fb (nl rt.list) and lb = local fb (nl rt.list) and n = local fb I32 and i = local fb I32 and out = local fb (nn rt.vals) in
      let shape = local fb (nl rt.list) in
      let cell l x = [ Lget l; ref_is_null; If (Bval v, [ Lget x ], [ Lget l; as_non_null; Lget i; call rt "elem" ]) ] in
      [ Lget 1; Test (false, T rt.list); If (Bnone, [ Lget 1; Cast (false, T rt.list); Lset la ], []);
        Lget 2; Test (false, T rt.list); If (Bnone, [ Lget 2; Cast (false, T rt.list); Lset lb ], []);
        Lget la; ref_is_null; If (Bval (nl rt.list), [ Lget lb ], [ Lget la ]); Lset shape;
        Lget la; ref_is_null; Lget lb; ref_is_null; i32_or; i32_eqz;
        If (Bnone, [
            Lget la; struct_get rt.list l_rows; Lget lb; struct_get rt.list l_rows; i32_ne;
            Lget la; struct_get rt.list l_cols; Lget lb; struct_get rt.list l_cols; i32_ne; i32_or;
            If (Bnone, fail rt shape_msg [ [ Lget la; as_non_null; call rt "sizes" ]; [ Lget lb; as_non_null; call rt "sizes" ] ] [ Lget 3 ], []) ], []);
        Lget shape; struct_get rt.list l_rows; Lget shape; struct_get rt.list l_cols; i32_mul; Lset n;
        Lget n; array_new_default rt.vals; Lset out ]
      @ upto i n ([ Lget out; Lget i; Lget 0 ] @ cell la 1 @ cell lb 2 @ cellwise rt @ [ array_set rt.vals ])
      @ [ Lget shape; struct_get rt.list l_rows; Lget shape; struct_get rt.list l_cols; Lget out; call rt "list_of" ]))
    (* One for each operation, so that a program that only adds arrays holds no comparison. *)
    [ "broadcast:arith", (fun rt -> [ Lget 3; call rt "arith" ]); "broadcast:cmp", (fun rt -> [ Lget 3; call rt "cmp" ]);
      "broadcast:eqv", (fun rt -> [ call rt "eqv" ]) ];
  (* -x: by its kind; an array cell by cell. *)
  def "neg" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let l = local fb (nl rt.list) and i = local fb I32 and n = local fb I32 and out = local fb (nn rt.vals) in
      [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Lget 0; call rt "kind"; Br_table ([ 0; 1; 2; 3 ], 4) ]);
                                                                        Lget 0; call rt "as_int"; Lget 1; call rt "neg_i"; call rt "box_i"; ret ]);
                                                        Lget 0; call rt "float_of"; f64_neg; call rt "box_f"; ret ]);
                                        missing; ret ]);
                        Lget 0; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; Lset n; Lget n; array_new_default rt.vals; Lset out ]
                      @ upto i n [ Lget out; Lget i; Lget l; as_non_null; Lget i; call rt "elem"; Lget 1; call rt "neg"; array_set rt.vals ]
                      @ [ Lget l; struct_get rt.list l_rows; Lget l; struct_get rt.list l_cols; Lget out; call rt "list_of"; ret ]) ]
      @ fail rt (Messages.negate a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ])


(* Comparisons: op 0 <, 1 <=, 2 >, 3 >=, as Arith.order: true, false or missing. *)
let syms = [| "<"; "<="; ">"; ">=" |]

(* The test of an order [c], -1, 0 or 1 (2 for NaN, never true), for op. *)
let order_test op c =
  [ Lget c; I32 2; i32_eq;
    If (Bval I32, [ I32 0 ],
        [ Lget op; I32 0; i32_eq;
          If (Bval I32, [ Lget c; I32 0; i32_lt_s ],
              [ Lget op; I32 1; i32_eq;
                If (Bval I32, [ Lget c; I32 0; i32_le_s ],
                    [ Lget op; I32 2; i32_eq; If (Bval I32, [ Lget c; I32 0; i32_gt_s ], [ Lget c; I32 0; i32_ge_s ]) ]) ]) ]) ]

let () =
  def "fcmp" (fun _ -> [ F64; F64 ], [ I32 ], fun _ ->
      [ Lget 0; Lget 1; f64_lt; If (Bnone, [ I32 (-1); ret ], []);
        Lget 0; Lget 1; f64_gt; If (Bnone, [ I32 1; ret ], []);
        Lget 0; Lget 1; f64_eq; If (Bval I32, [ I32 0 ], [ I32 2 ]) ]);
  def "text_cmp" (fun rt -> [ nn rt.bytes; nn rt.bytes ], [ I32 ], fun fb ->
      let i = local fb I32 and n = local fb I32 and x = local fb I32 and y = local fb I32 in
      [ Lget 0; array_len; Lget 1; array_len; Op 0x4d (* le_u *); If (Bval I32, [ Lget 0; array_len ], [ Lget 1; array_len ]); Lset n ]
      @ upto i n [ Lget 0; Lget i; array_get_u rt.bytes; Lset x; Lget 1; Lget i; array_get_u rt.bytes; Lset y;
                   Lget x; Lget y; i32_ne; If (Bnone, [ Lget x; Lget y; i32_gt_u; Lget x; Lget y; i32_lt_u; i32_sub; ret ], []) ]
      @ [ Lget 0; array_len; Lget 1; array_len; i32_gt_u; Lget 0; array_len; Lget 1; array_len; i32_lt_u; i32_sub ]);
  def "cmp" (fun rt -> [ I32; v; v; I32 ], [ v ], fun fb ->
      let c = local fb I32 in
      let a = 1 and b = 2 in
      let res = [ Lset c ] @ order_test 0 c @ bool_of rt @ [ ret ] in
      let isn x = [ Lget x; call rt "is_int"; Lget x; Test (false, T rt.boxf); i32_or ] in
      let bad k = fail rt (Messages.compare_op a1 syms.(k) a2) [ [ Lget a; call rt "describe" ]; [ Lget b; call rt "describe" ] ] [ Lget 3 ] in
      [ Lget a; Test (false, T rt.list); Lget b; Test (false, T rt.list); i32_or;
        If (Bnone, [ Lget 0; Lget a; Lget b; Lget 3; call rt "broadcast:cmp"; ret ], []);
        Lget a; call rt "is_int";
        If (Bnone, [ Lget b; call rt "is_int";
                     If (Bnone, [ Lget a; call rt "int_of"; Lget b; call rt "int_of"; i64_gt_s; Lget a; call rt "int_of"; Lget b; call rt "int_of"; i64_lt_s; i32_sub ] @ res, []);
                     Lget b; Test (false, T rt.boxf); If (Bnone, [ Lget a; call rt "int_of"; Lget b; call rt "float_of"; call rt "int_float" ] @ res, []) ], []);
        Lget a; Test (false, T rt.boxf);
        If (Bnone, [ Lget b; Test (false, T rt.boxf); If (Bnone, [ Lget a; call rt "float_of"; Lget b; call rt "float_of"; call rt "fcmp" ] @ res, []);
                     Lget b; call rt "is_int";
                     If (Bnone, [ Lget b; call rt "int_of"; Lget a; call rt "float_of"; call rt "int_float"; Lset c;
                                  Lget c; I32 2; i32_eq; If (Bval I32, [ I32 2 ], [ I32 0; Lget c; i32_sub ]) ] @ res, []) ], []);
        Lget a; Test (false, T rt.bytes); Lget b; Test (false, T rt.bytes); i32_and;
        If (Bnone, [ Lget a; Cast (false, T rt.bytes); Lget b; Cast (false, T rt.bytes); call rt "text_cmp" ] @ res, []);
        (* missing with numbers or missing *)
        Lget a; ref_is_null; Lget b; ref_is_null ] @ isn b @ [ i32_or; i32_and; Lget b; ref_is_null ] @ isn a @ [ i32_and; i32_or;
        If (Bnone, [ missing; ret ], []);
        Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Block (Bnone, [ Lget 0; Br_table ([ 0; 1; 2 ], 3) ]) ] @ bad 0) ] @ bad 1) ] @ bad 2) ]
      @ bad 3);
  (* == and !=: op 0 and 1, Arith.eq: floats as floats, NaN apart; anything else Value.equal; arrays cell by cell. *)
  def "eqv" (fun rt -> [ I32; v; v ], [ v ], fun _ ->
      [ Lget 1; Test (false, T rt.list); Lget 2; Test (false, T rt.list); i32_or;
        If (Bnone, [ Lget 0; Lget 1; Lget 2; I32 (-1); call rt "broadcast:eqv"; ret ], []);
        Lget 1; Test (false, T rt.boxf); Lget 2; Test (false, T rt.boxf); i32_and;
        If (Bval I32, [ Lget 1; call rt "float_of"; Lget 2; call rt "float_of"; f64_eq ], [ Lget 1; Lget 2; call rt "equal" ]);
        Lget 0; i32_xor ] @ bool_of rt);
  (* A condition: true or false, else the error. *)
  def "truth" (fun rt -> [ v; I32 ], [ I32 ], fun _ ->
      [ Lget 0; g_true rt; ref_eq; If (Bnone, [ I32 1; ret ], []);
        Lget 0; g_false rt; ref_eq; If (Bnone, [ I32 0; ret ], []) ]
      @ fail rt (Messages.condition a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ])

(* Lists. *)
let () =
  (* An array of these cells, as Arrays.of_vals: all floats an F store, all integers an I store, else values. *)
  def "list_of" (fun rt -> [ I32; I32; nn rt.vals ], [ v ], fun fb ->
      let n = local fb I32 and i = local fb I32 and fl = local fb I32 and it = local fb I32 in
      let fs = local fb (nn rt.f64s) and is = local fb (nn rt.i64s) in
      [ Lget 0; Lget 1; i32_mul; Lset n; Lget n; I32 0; i32_ne; Lset fl; Lget fl; Lset it ]
      @ upto i n [ Lget 2; Lget i; array_get rt.vals; Test (false, T rt.boxf); Lget fl; i32_and; Lset fl;
                   Lget 2; Lget i; array_get rt.vals; call rt "is_int"; Lget it; i32_and; Lset it ]
      @ [ Lget fl;
          If (Bnone, [ Lget n; array_new_default rt.f64s; Lset fs ]
                     @ upto i n [ Lget fs; Lget i; Lget 2; Lget i; array_get rt.vals; call rt "float_of"; array_set rt.f64s ]
                     @ [ I32 1; Lget 0; Lget 1; Lget fs; I32 1; struct_new rt.list; ret ], []);
          Lget it;
          If (Bnone, [ Lget n; array_new_default rt.i64s; Lset is ]
                     @ upto i n [ Lget is; Lget i; Lget 2; Lget i; array_get rt.vals; call rt "int_of"; array_set rt.i64s ]
                     @ [ I32 1; Lget 0; Lget 1; Lget is; I32 1; struct_new rt.list; ret ], []);
          I32 1; Lget 0; Lget 1; Lget 2; I32 1; struct_new rt.list ]);
  def "cells" (fun rt -> [ nn rt.list ], [ I32 ], fun _ ->
      [ Lget 0; struct_get rt.list l_rows; Lget 0; struct_get rt.list l_cols; i32_mul ]);
  (* "1 by 3": the sizes of a message. *)
  def "sizes" (fun rt -> [ nn rt.list ], [ nn rt.bytes ], fun fb ->
      let x = local fb (nn rt.buf) in
      [ call rt "buf_new"; Lset x; Lget x; Lget 0; struct_get rt.list l_rows; i64_extend_u; call rt "write_int";
        Lget x; text rt " by "; call rt "buf_add"; Lget x; Lget 0; struct_get rt.list l_cols; i64_extend_u; call rt "write_int";
        Lget x; call rt "buf_done" ]);
  (* An owned copy, its store cut to its cells. *)
  def "copy_list" (fun rt -> [ nn rt.list ], [ nn rt.list ], fun fb ->
      let n = local fb I32 and s = local fb (Ref (false, Array)) and f = local fb (nn rt.f64s) and i = local fb (nn rt.i64s) and w = local fb (nn rt.vals) in
      [ Lget 0; call rt "cells"; Lset n; Lget 0; struct_get rt.list l_store; Lset s;
        Block (Bnone, [
            Lget s; Test (false, T rt.f64s);
            If (Bnone, [ Lget n; array_new_default rt.f64s; Lset f; Lget f; I32 0; Lget s; Cast (false, T rt.f64s); I32 0; Lget n; array_copy rt.f64s rt.f64s; Lget f; Lset s; Br 1 ], []);
            Lget s; Test (false, T rt.i64s);
            If (Bnone, [ Lget n; array_new_default rt.i64s; Lset i; Lget i; I32 0; Lget s; Cast (false, T rt.i64s); I32 0; Lget n; array_copy rt.i64s rt.i64s; Lget i; Lset s; Br 1 ], []);
            Lget n; array_new_default rt.vals; Lset w; Lget w; I32 0; Lget s; Cast (false, T rt.vals); I32 0; Lget n; array_copy rt.vals rt.vals;
            Lget w; Lget n; call rt "share_all"; Lget w; Lset s ]);
        I32 1; Lget 0; struct_get rt.list l_rows; Lget 0; struct_get rt.list l_cols; Lget s; I32 1; struct_new rt.list ]);
  (* The cells of a copy: each one held twice now. *)
  def "share_all" (fun rt -> [ nn rt.vals; I32 ], [], fun fb ->
      let i = local fb I32 in
      upto i 1 [ Lget 0; Lget i; array_get rt.vals; call rt "share"; drop ]);
  (* The store as values, for a cell of another kind: Arrays.store_elt. *)
  def "to_vals" (fun rt -> [ nn rt.list ], [ nn rt.vals ], fun fb ->
      let n = local fb I32 and i = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 0; struct_get rt.list l_store; Test (false, T rt.vals);
        If (Bnone, [ Lget 0; struct_get rt.list l_store; Cast (false, T rt.vals); ret ], []);
        Lget 0; struct_get rt.list l_store; array_len; Lset n; Lget n; array_new_default rt.vals; Lset w ]
      @ upto i n [ Lget w; Lget i; Lget 0; Lget i; call rt "elem"; array_set rt.vals ]
      @ [ Lget 0; Lget w; struct_set rt.list l_store; Lget w ]);
  (* Writes cell k, from 0, of a list: an F store takes an integer as a float. *)
  def "store_elt" (fun rt -> [ nn rt.list; I32; v ], [], fun _ ->
      [ Lget 0; struct_get rt.list l_store; Test (false, T rt.f64s);
        If (Bnone, [ Lget 2; Test (false, T rt.boxf); Lget 2; call rt "is_int"; i32_or;
                     If (Bnone, [ Lget 0; struct_get rt.list l_store; Cast (false, T rt.f64s); Lget 1; Lget 2; call rt "as_float"; array_set rt.f64s; ret ], []) ], []);
        Lget 0; struct_get rt.list l_store; Test (false, T rt.i64s);
        If (Bnone, [ Lget 2; call rt "is_int";
                     If (Bnone, [ Lget 0; struct_get rt.list l_store; Cast (false, T rt.i64s); Lget 1; Lget 2; call rt "int_of"; array_set rt.i64s; ret ], []) ], []);
        Lget 0; call rt "to_vals"; Lget 1; Lget 2; array_set rt.vals ]);
  (* Clears the ownership of a list, map or struct: a second reference is about to lead to it. *)
  def "share" (fun rt -> [ v ], [ v ], fun _ ->
      [ Block (Bnone, [ Block (Bval (nn rt.own), [ Lget 0; Br_on_cast (0, true, Eq, false, T rt.own); Br 1 ]); I32 0; struct_set rt.own 0 ]);
        Lget 0 ]);
  (* xs[i], i a whole number. *)
  def "index" (fun rt -> [ v; I64; I32 ], [ v ], fun fb ->
      let l = local fb (nl rt.list) in
      [ Lget 0; Test (false, T rt.list);
        If (Bnone, [ Lget 0; Cast (false, T rt.list); Lset l;
                     Lget 1; i64 1; i64_lt_s; Lget 1; Lget l; as_non_null; call rt "cells"; i64_extend_u; i64_gt_s; i32_or;
                     If (Bnone, fail ~kind:k_index rt (Messages.index_outside 1000001 1000002 |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
                                  [ [ Lget 1; call rt "itoa" ]; [ Lget l; as_non_null; call rt "cells"; i64_extend_u; call rt "itoa" ] ] [ Lget 2 ], []);
                     Lget l; as_non_null; Lget 1; i32_wrap; I32 1; i32_sub; call rt "elem"; ret ], []);
        (* A dictionary: the integer is its key. *)
        Lget 0; Test (false, T rt.map); Lget 0; Test (false, T rt.smap); i32_or; If (Bnone, [ Lget 0; Lget 1; call rt "box_i"; Lget 2; call rt "index_v"; ret ], []) ]
      @ fail rt (Messages.index_value a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 2 ]);
  (* An index of any type: a whole number, or a float of one. *)
  def "whole" (fun rt -> [ v; I32 ], [ I64 ], fun fb ->
      let x = local fb F64 in
      [ Lget 0; call rt "is_int"; If (Bnone, [ Lget 0; call rt "int_of"; ret ], []);
        Lget 0; Test (false, T rt.boxf);
        If (Bnone, [ Lget 0; call rt "float_of"; Lset x; Lget x; f64_trunc; Lget x; f64_eq; Lget x; f64_abs; F64 4e18; f64_lt; i32_and;
                     If (Bnone, [ Lget x; i64_trunc_sat; ret ], []) ], []) ]
      @ fail rt (Messages.index_type a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
  def "range_bound" (fun rt -> [ v; I32 ], [ I64 ], fun fb ->
      let x = local fb F64 in
      [ Lget 0; call rt "is_int"; If (Bnone, [ Lget 0; call rt "int_of"; ret ], []);
        Lget 0; Test (false, T rt.boxf);
        If (Bnone, [ Lget 0; call rt "float_of"; Lset x; Lget x; f64_trunc; Lget x; f64_eq; Lget x; f64_abs; F64 4e18; f64_lt; i32_and;
                     If (Bnone, [ Lget x; i64_trunc_sat; ret ], []) ], []) ]
      @ fail rt (Messages.range_bound a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
  (* xs[i] = x: the list to keep in the variable, the same one when owned, else a copy. *)
  def "set_index" (fun rt -> [ v; I64; v; I32 ], [ v ], fun fb ->
      let l = local fb (nl rt.list) in
      [ Lget 0; Test (false, T rt.list);
        If (Bnone, [ Lget 0; Cast (false, T rt.list); Lset l;
                     Lget l; struct_get rt.list l_owned; i32_eqz; If (Bnone, [ Lget l; as_non_null; call rt "copy_list"; Lset l ], []);
                     Lget 1; i64 1; i64_lt_s; Lget 1; Lget l; as_non_null; call rt "cells"; i64_extend_u; i64_gt_s; i32_or;
                     If (Bnone, fail ~kind:k_index rt (Messages.index_outside 1000001 1000002 |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
                                  [ [ Lget 1; call rt "itoa" ]; [ Lget l; as_non_null; call rt "cells"; i64_extend_u; call rt "itoa" ] ] [ Lget 3 ], []);
                     Lget l; as_non_null; Lget 1; i32_wrap; I32 1; i32_sub; Lget 2; call rt "store_elt"; Lget l; ret ], []);
        Lget 0; Test (false, T rt.map); Lget 0; Test (false, T rt.smap); i32_or; If (Bnone, [ Lget 0; Lget 1; call rt "box_i"; Lget 2; Lget 3; call rt "set_field"; ret ], []) ]
      @ fail rt (Messages.index_value a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 3 ]);
  (* a..b, of integers. *)
  def "range" (fun rt -> [ I64; I64; I32 ], [ v ], fun fb ->
      let n = local fb I32 and i = local fb I32 and d = local fb (nn rt.i64s) in
      [ Lget 1; Lget 0; i64_ge_s; Lget 1; Lget 0; i64_sub; i64 (1 lsl 28); i64_ge_s; i32_and;
        If (Bnone, fail rt Messages.range_too_long [] [ Lget 2 ], []);
        Lget 1; Lget 0; i64_lt_s; If (Bval I32, [ I32 0 ], [ Lget 1; Lget 0; i64_sub; i32_wrap; I32 1; i32_add ]); Lset n;
        Lget n; array_new_default rt.i64s; Lset d ]
      @ upto i n [ Lget d; Lget i; Lget 0; Lget i; i64_extend_u; i64_add; array_set rt.i64s ]
      @ [ I32 1; I32 1; Lget n; Lget d; I32 1; struct_new rt.list ]);
  (* A list being built, by a comprehension: values, room for more; [built] gives the list. *)
  def "builder" (fun rt -> [], [ nn rt.list ], fun _ -> [ I32 1; I32 1; I32 0; I32 8; array_new_default rt.vals; I32 1; struct_new rt.list ]);
  def "push" (fun rt -> [ nn rt.list; v ], [], fun fb ->
      let n = local fb I32 and s = local fb (nn rt.vals) and w = local fb (nn rt.vals) in
      [ Lget 0; struct_get rt.list l_cols; Lset n; Lget 0; struct_get rt.list l_store; Cast (false, T rt.vals); Lset s;
        Lget n; Lget s; array_len; i32_ge_u;
        If (Bnone, [ Lget n; I32 2; i32_mul; array_new_default rt.vals; Lset w; Lget w; I32 0; Lget s; I32 0; Lget n; array_copy rt.vals rt.vals;
                     Lget 0; Lget w; struct_set rt.list l_store; Lget w; Lset s ], []);
        Lget s; Lget n; Lget 1; array_set rt.vals; Lget 0; Lget n; I32 1; i32_add; struct_set rt.list l_cols ]);
  def "built" (fun rt -> [ nn rt.list ], [ v ], fun fb ->
      let n = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 0; struct_get rt.list l_cols; Lset n; Lget n; array_new_default rt.vals; Lset w;
        Lget w; I32 0; Lget 0; struct_get rt.list l_store; Cast (false, T rt.vals); I32 0; Lget n; array_copy rt.vals rt.vals;
        Lget n; If (Bval I32, [ I32 1 ], [ I32 1 ]); Lget n; Lget w; call rt "list_of" ]);
  (* value.Len *)
  def "len" (fun rt -> [ v ], [ I64 ], fun _ ->
      [ Lget 0; Test (false, T rt.list); If (Bnone, [ Lget 0; Cast (false, T rt.list); call rt "cells"; i64_extend_u; ret ], []);
        Lget 0; Test (false, T rt.bytes);
        If (Bnone, [ Lget 0; Cast (false, T rt.bytes); call rt "code_points"; i64_extend_u; ret ], []);
        Lget 0; Test (false, T rt.map); If (Bnone, [ Lget 0; Cast (false, T rt.map); struct_get rt.map m_count; i64_extend_u; ret ], []);
        Lget 0; Test (false, T rt.smap); If (Bnone, [ Lget 0; Cast (false, T rt.smap); struct_get rt.smap s_keys; struct_get rt.keys k_names; array_len; i64_extend_u; ret ], []);
        Lget 0; Test (false, T rt.recd); If (Bnone, [ Lget 0; Cast (false, T rt.recd); struct_get rt.recd r_fields; array_len; i64_extend_u; ret ], []);
        i64 1 ]);
  def "code_points" (fun rt -> [ nn rt.bytes ], [ I32 ], fun fb ->
      let i = local fb I32 and n = local fb I32 and c = local fb I32 in
      [ Lget 0; array_len; Lset n ]
      @ upto i n [ Lget 0; Lget i; array_get_u rt.bytes; I32 0xc0; i32_and; I32 0x80; i32_ne; Lget c; i32_add; Lset c ]
      @ [ Lget c ])

(* Equality of whole values: Value.equal. *)
let () =
  def "bytes_eq" (fun rt -> [ nn rt.bytes; nn rt.bytes ], [ I32 ], fun fb ->
      let i = local fb I32 and n = local fb I32 in
      [ Lget 0; array_len; Lget 1; array_len; i32_ne; If (Bnone, [ I32 0; ret ], []); Lget 0; array_len; Lset n ]
      @ upto i n [ Lget 0; Lget i; array_get_u rt.bytes; Lget 1; Lget i; array_get_u rt.bytes; i32_ne; If (Bnone, [ I32 0; ret ], []) ]
      @ [ I32 1 ]);
  (* The place of a name in an array of texts, or -1. *)
  def "find_name" (fun rt -> [ nn rt.vals; nn rt.bytes ], [ I32 ], fun fb ->
      let i = local fb I32 and n = local fb I32 in
      [ Lget 0; array_len; Lset n ]
      @ upto i n [ Lget 0; Lget i; array_get rt.vals; Cast (false, T rt.bytes); Lget 1; call rt "bytes_eq"; If (Bnone, [ Lget i; ret ], []) ]
      @ [ I32 (-1) ]);
  def "equal" (fun rt -> [ v; v ], [ I32 ], fun fb ->
      let la = local fb (nl rt.list) and lb = local fb (nl rt.list) and n = local fb I32 and i = local fb I32 and k = local fb I32 in
      let ma = local fb (nl rt.map) and mb = local fb (nl rt.map) and ra = local fb (nl rt.recd) and rb = local fb (nl rt.recd) in
      let x = local fb F64 and y = local fb F64 in
      [ Lget 0; Lget 1; ref_eq; If (Bnone, [ I32 1; ret ], []);
        Lget 0; ref_is_null; Lget 1; ref_is_null; i32_or; If (Bnone, [ I32 0; ret ], []);
        Lget 0; Test (false, T rt.smap); Lget 1; Test (false, T rt.smap); i32_or;
        If (Bnone, [ Lget 0; call rt "as_map"; Lget 1; call rt "as_map"; call rt "equal"; ret ], []);
        Lget 0; call rt "is_int";
        If (Bnone, [ Lget 1; call rt "is_int"; If (Bnone, [ Lget 0; call rt "int_of"; Lget 1; call rt "int_of"; i64_eq; ret ], []);
                     Lget 1; Test (false, T rt.boxf); If (Bnone, [ Lget 0; call rt "int_of"; Lget 1; call rt "float_of"; call rt "int_float"; i32_eqz; ret ], []);
                     I32 0; ret ], []);
        Lget 0; Test (false, T rt.boxf);
        If (Bnone, [ Lget 1; call rt "is_int"; If (Bnone, [ Lget 1; call rt "int_of"; Lget 0; call rt "float_of"; call rt "int_float"; i32_eqz; ret ], []);
                     Lget 1; Test (false, T rt.boxf); i32_eqz; If (Bnone, [ I32 0; ret ], []);
                     Lget 0; call rt "float_of"; Lset x; Lget 1; call rt "float_of"; Lset y;
                     Lget x; Lget y; f64_eq; Lget x; Lget x; f64_ne; Lget y; Lget y; f64_ne; i32_and; i32_or; ret ], []);
        Lget 0; Test (false, T rt.bytes);
        If (Bnone, [ Lget 1; Test (false, T rt.bytes); If (Bval I32, [ Lget 0; Cast (false, T rt.bytes); Lget 1; Cast (false, T rt.bytes); call rt "bytes_eq" ], [ I32 0 ]); ret ], []);
        Lget 0; Test (false, T rt.list);
        If (Bnone, [ Lget 1; Test (false, T rt.list); i32_eqz; If (Bnone, [ I32 0; ret ], []);
                     Lget 0; Cast (false, T rt.list); Lset la; Lget 1; Cast (false, T rt.list); Lset lb;
                     Lget la; as_non_null; call rt "cells"; i32_eqz; Lget lb; as_non_null; call rt "cells"; i32_eqz; i32_and; If (Bnone, [ I32 1; ret ], []);
                     Lget la; struct_get rt.list l_rows; Lget lb; struct_get rt.list l_rows; i32_ne;
                     Lget la; struct_get rt.list l_cols; Lget lb; struct_get rt.list l_cols; i32_ne; i32_or; If (Bnone, [ I32 0; ret ], []);
                     Lget la; as_non_null; call rt "cells"; Lset n ]
                   @ upto i n [ Lget la; as_non_null; Lget i; call rt "elem"; Lget lb; as_non_null; Lget i; call rt "elem"; call rt "equal"; i32_eqz; If (Bnone, [ I32 0; ret ], []) ]
                   @ [ I32 1; ret ], []);
        Lget 0; Test (false, T rt.recd);
        If (Bnone, [ Lget 1; Test (false, T rt.recd); i32_eqz; If (Bnone, [ I32 0; ret ], []);
                     Lget 0; Cast (false, T rt.recd); Lset ra; Lget 1; Cast (false, T rt.recd); Lset rb;
                     Lget ra; struct_get rt.recd r_shape; struct_get rt.shape 0; Lget rb; struct_get rt.recd r_shape; struct_get rt.shape 0; call rt "bytes_eq"; i32_eqz;
                     Lget ra; struct_get rt.recd r_fields; array_len; Lget rb; struct_get rt.recd r_fields; array_len; i32_ne; i32_or; If (Bnone, [ I32 0; ret ], []);
                     Lget ra; struct_get rt.recd r_fields; array_len; Lset n ]
                   @ upto i n [ Lget rb; struct_get rt.recd r_shape; struct_get rt.shape 1; Lget ra; struct_get rt.recd r_shape; struct_get rt.shape 1; Lget i; array_get rt.vals;
                                Cast (false, T rt.bytes); call rt "find_name"; Lset k;
                                Lget k; I32 0; i32_lt_s; If (Bnone, [ I32 0; ret ], []);
                                Lget ra; struct_get rt.recd r_fields; Lget i; array_get rt.vals; Lget rb; struct_get rt.recd r_fields; Lget k; array_get rt.vals;
                                call rt "equal"; i32_eqz; If (Bnone, [ I32 0; ret ], []) ]
                   @ [ I32 1; ret ], []);
        Lget 0; Test (false, T rt.map);
        If (Bnone, [ Lget 1; Test (false, T rt.map); i32_eqz; If (Bnone, [ I32 0; ret ], []);
                     Lget 0; Cast (false, T rt.map); Lset ma; Lget 1; Cast (false, T rt.map); Lset mb;
                     Lget ma; struct_get rt.map m_count; Lget mb; struct_get rt.map m_count; i32_ne; If (Bnone, [ I32 0; ret ], []);
                     Lget ma; struct_get rt.map m_count; Lset n ]
                   @ upto i n [ Lget mb; as_non_null; Lget ma; struct_get rt.map m_keys; struct_get rt.keys k_names; Lget i; array_get rt.vals;
                                call rt "map_find"; Lset k;
                                Lget k; I32 0; i32_lt_s; If (Bnone, [ I32 0; ret ], []);
                                Lget ma; struct_get rt.map m_vals; Lget i; array_get rt.vals; Lget mb; struct_get rt.map m_vals; Lget k; array_get rt.vals;
                                call rt "equal"; i32_eqz; If (Bnone, [ I32 0; ret ], []) ]
                   @ [ I32 1; ret ], []);
        I32 0 ])

(* Maps: a name found by its hash past 8 names, as Python 3.6's compact dict (after Raymond Hettinger), which the native
   runtime keeps for a map that nothing else holds: at most half of the slots used, a name there is found in 1.5 probes on
   average and one that isn't in 2.5 (Knuth, vol. 3, 6.4). The hash takes a seed drawn at random for each table, so that
   nobody outside can choose names that fall together; a new name that probes past 128 slots means names that do, and
   the table is made again with another seed. *)
let probe_limit = 128
let table_from = 8
let high32 = Int64.shift_left (-1L) 32

let () =
  (* A seed: splitmix64 (Steele, Lea and Flood, OOPSLA 2014) from 64 random bits of the loader, drawn at the first. *)
  def "next_seed" (fun rt -> [], [ I64 ], fun fb ->
      let z = local fb I64 in
      let g = gl rt "seed" I64 true [ I64 0L ] in
      [ Gget g; i64_eqz;
        If (Bnone, [ host rt "rand32"; i64_extend_u; i64 32; i64_shl; host rt "rand32"; i64_extend_u; i64_or; i64 1; i64_or; Gset g ], []);
        Gget g; I64 0x9E3779B97F4A7C15L; i64_add; Gset g; Gget g; Lset z;
        Lget z; Lget z; i64 30; i64_shr_u; i64_xor; I64 0xBF58476D1CE4E5B9L; i64_mul; Lset z;
        Lget z; Lget z; i64 27; i64_shr_u; i64_xor; I64 0x94D049BB133111EBL; i64_mul; Lset z;
        Lget z; Lget z; i64 31; i64_shr_u; i64_xor ]);
  (* The hash of a text, as the native's: its count and seed, a multiply a byte (FNV's prime), then mixed. *)
  def "hash" (fun rt -> [ nn rt.bytes; I64 ], [ I64 ], fun fb ->
      let h = local fb I64 and i = local fb I32 and n = local fb I32 in
      [ Lget 0; array_len; Lset n; Lget 1; Lget n; i64_extend_u; i64_xor; Lset h ]
      @ upto i n [ Lget h; Lget 0; Lget i; array_get_u rt.bytes; i64_extend_u; i64_xor; I64 0x100000001b3L; i64_mul; Lset h ]
      @ [ Lget h; Lget h; i64 32; i64_shr_u; i64_xor; I64 0x2545F4914F6CDD1DL; i64_mul; Lset h;
          Lget h; Lget h; i64 29; i64_shr_u; i64_xor ]);
  (* Two keys the same, as Trie.compare_keys: texts by their bytes, numbers by their value, 1 as 1.0. *)
  def "key_eq" (fun rt -> [ v; v ], [ I32 ], fun _ ->
      [ Lget 0; Lget 1; ref_eq; If (Bnone, [ I32 1; ret ], []);
        Lget 0; Test (false, T rt.bytes);
        If (Bnone, [ Lget 1; Test (false, T rt.bytes); If (Bval I32, [ Lget 0; Cast (false, T rt.bytes); Lget 1; Cast (false, T rt.bytes); call rt "bytes_eq" ], [ I32 0 ]); ret ], []);
        Lget 1; Test (false, T rt.bytes); If (Bnone, [ I32 0; ret ], []);
        Lget 0; Lget 1; call rt "equal" ]);
  (* The hash of a key: a text's, or a number's from its value, an integer's and its float's the same. *)
  def "key_hash" (fun rt -> [ v; I64 ], [ I64 ], fun fb ->
      let x = local fb F64 and h = local fb I64 in
      [ Lget 0; Test (false, T rt.bytes); If (Bnone, [ Lget 0; Cast (false, T rt.bytes); Lget 1; call rt "hash"; ret ], []);
        Lget 0; call rt "is_int"; If (Bval I64, [ Lget 0; call rt "int_of" ],
                                       [ Lget 0; call rt "as_float"; Ltee x; f64_trunc; Lget x; f64_eq; Lget x; f64_abs; F64 4e18; f64_lt; i32_and;
                                         If (Bval I64, [ Lget x; i64_trunc_sat ], [ Lget x; Op 0xbd (* i64.reinterpret_f64 *) ]) ]);
        Lget 1; i64_xor; I64 0x9E3779B97F4A7C15L; i64_mul; Lset h; Lget h; Lget h; i64 32; i64_shr_u; i64_xor ]);
  (* The place of a key in a map, or -1. *)
  def "map_find" (fun rt -> [ nn rt.map; v ], [ I32 ], fun fb ->
      let k = local fb (nn rt.keys) and names = local fb (nn rt.vals) and i = local fb I32 and n = local fb I32 in
      let slots = local fb (nn rt.i64s) and h = local fb I64 and mask = local fb I32 and sl = local fb I64 and e = local fb I32 in
      [ Lget 0; struct_get rt.map m_keys; Lset k; Lget k; struct_get rt.keys k_names; Lset names;
        Lget k; struct_get rt.keys k_slots; ref_is_null;
        If (Bnone, [ Lget 0; struct_get rt.map m_count; Lset n;
                     Lget 1; Test (false, T rt.bytes);
                     If (Bnone, upto i n [ Lget names; Lget i; array_get rt.vals; Test (false, T rt.bytes);
                                           If (Bnone, [ Lget names; Lget i; array_get rt.vals; Cast (false, T rt.bytes); Lget 1; Cast (false, T rt.bytes); call rt "bytes_eq";
                                                        If (Bnone, [ Lget i; ret ], []) ], []) ]
                                @ [ I32 (-1); ret ], []) ]
                   @ upto i n [ Lget names; Lget i; array_get rt.vals; Lget 1; call rt "key_eq"; If (Bnone, [ Lget i; ret ], []) ]
                   @ [ I32 (-1); ret ], []);
        Lget k; struct_get rt.keys k_slots; as_non_null; Lset slots;
        Lget slots; array_len; I32 1; i32_sub; Lset mask;
        Lget 1; Lget k; struct_get rt.keys k_seed; call rt "key_hash"; Lset h;
        Lget h; i32_wrap; Lget mask; i32_and; Lset i;
        Loop (Bnone, [
            Lget slots; Lget i; array_get rt.i64s; Lset sl;
            Lget sl; i64_eqz; If (Bnone, [ I32 (-1); ret ], []);
            Lget sl; Lget h; i64_xor; i64 32; i64_shr_u; i64_eqz;
            If (Bnone, [ Lget sl; i32_wrap; I32 1; i32_sub; Lset e;
                         Lget names; Lget e; array_get rt.vals; Lget 1; call rt "key_eq"; If (Bnone, [ Lget e; ret ], []) ], []);
            Lget i; I32 1; i32_add; Lget mask; i32_and; Lset i; Br 0 ]);
        unreachable ]);
  (* Name [e] in a table: false when its probe passes the limit. *)
  def "slot_put" (fun rt -> [ nn rt.i64s; I64; v; I32 ], [ I32 ], fun fb ->
      let h = local fb I64 and i = local fb I32 and mask = local fb I32 and d = local fb I32 in
      [ Lget 2; Lget 1; call rt "key_hash"; Lset h;
        Lget 0; array_len; I32 1; i32_sub; Lset mask; Lget h; i32_wrap; Lget mask; i32_and; Lset i;
        Block (Bnone, [ Loop (Bnone, [
            Lget 0; Lget i; array_get rt.i64s; i64_eqz; Br_if 1;
            Lget i; I32 1; i32_add; Lget mask; i32_and; Lset i;
            Lget d; I32 1; i32_add; Ltee d; I32 probe_limit; i32_gt_u; If (Bnone, [ I32 0; ret ], []); Br 0 ]) ]);
        Lget 0; Lget i; Lget h; I64 high32; i64_and; Lget 3; I32 1; i32_add; i64_extend_u; i64_or; array_set rt.i64s; I32 1 ]);
  (* The keys of the first [n] of these names: past 8 of them, a table of twice [cap] slots, made again with another seed
     while a probe passes the limit. *)
  def "keys_of" (fun rt -> [ nn rt.vals; I32; I32 ], [ nn rt.keys ], fun fb ->
      let slots = local fb (nl rt.i64s) and seed = local fb I64 and i = local fb I32 and size = local fb I32 in
      [ Lget 1; I32 table_from; i32_le_u; If (Bnone, [ Lget 0; Rnull (T rt.i64s); I64 0L; struct_new rt.keys; ret ], []);
        Block (Bnone, [ Loop (Bnone, [
            call rt "next_seed"; Lset seed;
            (* Slots a power of two, at least twice the room: a mask then reaches each. *)
            I32 16; Lset size; Block (Bnone, [ Loop (Bnone, [ Lget size; Lget 2; I32 2; i32_mul; i32_ge_u; Br_if 1; Lget size; I32 2; i32_mul; Lset size; Br 0 ]) ]);
            Lget size; array_new_default rt.i64s; Lset slots;
            Block (Bnone, upto i 1 [ Lget slots; as_non_null; Lget seed; Lget 0; Lget i; array_get rt.vals; Lget i; call rt "slot_put"; i32_eqz; Br_if 2 ]
                          @ [ Br 2 ]);
            Br 0 ]) ]);
        Lget 0; Lget slots; Lget seed; struct_new rt.keys ]);
  (* A copy to write, owned, its values held twice now; its keys too, so neither map takes a new name in their room. *)
  def "map_copy" (fun rt -> [ nn rt.map ], [ nn rt.map ], fun fb ->
      let n = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 0; struct_get rt.map m_count; Lset n; Lget n; array_new_default rt.vals; Lset w;
        Lget w; I32 0; Lget 0; struct_get rt.map m_vals; I32 0; Lget n; array_copy rt.vals rt.vals; Lget w; Lget n; call rt "share_all";
        Lget 0; I32 0; struct_set rt.map m_mine;
        I32 1; Lget 0; struct_get rt.map m_keys; Lget w; Lget n; I32 0; struct_new rt.map ]);
  (* A new name and its value in an owned map: in the room of its keys when they are its alone, else in names and values
     twice as many, then its own. *)
  def "map_add" (fun rt -> [ nn rt.map; v; v ], [], fun fb ->
      let n = local fb I32 and k = local fb (nn rt.keys) and names = local fb (nn rt.vals) and cap = local fb I32 and w = local fb (nn rt.vals) in
      let remake = [ Lget 0; Lget names; Lget n; Lget names; array_len; call rt "keys_of"; struct_set rt.map m_keys ] in
      [ Lget 0; struct_get rt.map m_count; Lset n; Lget 0; struct_get rt.map m_keys; Lset k; Lget k; struct_get rt.keys k_names; Lset names;
        Lget 0; struct_get rt.map m_mine; i32_eqz; Lget n; Lget names; array_len; i32_eq; i32_or;
        If (Bnone,
            [ Lget n; I32 2; i32_mul; Lset cap; Lget cap; I32 8; i32_lt_u; If (Bnone, [ I32 8; Lset cap ], []);
              Lget cap; array_new_default rt.vals; Lset w; Lget w; I32 0; Lget names; I32 0; Lget n; array_copy rt.vals rt.vals; Lget w; Lset names;
              Lget cap; array_new_default rt.vals; Lset w; Lget w; I32 0; Lget 0; struct_get rt.map m_vals; I32 0; Lget n; array_copy rt.vals rt.vals;
              Lget 0; Lget w; struct_set rt.map m_vals;
              Lget names; Lget n; Lget 1; array_set rt.vals; Lget n; I32 1; i32_add; Lset n ]
            @ remake @ [ Lget 0; I32 1; struct_set rt.map m_mine ],
            [ Lget names; Lget n; Lget 1; array_set rt.vals; Lget n; I32 1; i32_add; Lset n;
              Lget k; struct_get rt.keys k_slots; ref_is_null;
              If (Bnone, [ Lget n; I32 table_from; i32_gt_u; If (Bnone, remake, []) ],
                  [ Lget k; struct_get rt.keys k_slots; as_non_null; Lget k; struct_get rt.keys k_seed; Lget 1; Lget n; I32 1; i32_sub; call rt "slot_put"; i32_eqz;
                    If (Bnone, remake, []) ]) ]);
        Lget 0; struct_get rt.map m_vals; Lget n; I32 1; i32_sub; Lget 2; array_set rt.vals;
        Lget 0; Lget n; struct_set rt.map m_count ])

(* Maps and structs: a field by its name, through the cache of the place that reads it. *)
let () =
  def "field" (fun rt -> [ v; nn rt.bytes; nn rt.cache; I32 ], [ v ], fun fb ->
      let sm = local fb (nl rt.smap) in
      let mp = local fb (nl rt.map) and rc = local fb (nl rt.recd) and k = local fb I32 and l = local fb (nl rt.list) and i = local fb I32 and n = local fb I32 and out = local fb (nn rt.vals) in
      [ Lget 0; Test (false, T rt.map);
        If (Bnone, [ Lget 0; Cast (false, T rt.map); Lset mp;
                     Lget mp; struct_get rt.map m_keys; Lget 2; struct_get rt.cache 0; ref_eq;
                     If (Bnone, [ Lget mp; struct_get rt.map m_vals; Lget 2; struct_get rt.cache 1; array_get rt.vals; ret ], []);
                     Lget mp; as_non_null; Lget 1; call rt "map_find"; Lset k;
                     Lget k; I32 0; i32_ge_s;
                     If (Bnone, [ Lget 2; Lget mp; struct_get rt.map m_keys; struct_set rt.cache 0; Lget 2; Lget k; struct_set rt.cache 1;
                                  Lget mp; struct_get rt.map m_vals; Lget k; array_get rt.vals; ret ], []) ]
                   @ fail ~kind:k_index rt (Messages.dict_absent a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 3 ], []);
        Lget 0; Test (false, T rt.smap);
        If (Bnone, [ Lget 0; Cast (false, T rt.smap); Lset sm;
                     Lget sm; struct_get rt.smap s_keys; Lget 2; struct_get rt.cache 0; ref_eq;
                     If (Bnone, [ Lget sm; as_non_null; Lget 2; struct_get rt.cache 1; call rt "sget"; ret ], []);
                     Lget sm; struct_get rt.smap s_keys; struct_get rt.keys k_names; Lget 1; call rt "find_name"; Lset k;
                     Lget k; I32 0; i32_ge_s;
                     If (Bnone, [ Lget 2; Lget sm; struct_get rt.smap s_keys; struct_set rt.cache 0; Lget 2; Lget k; struct_set rt.cache 1;
                                  Lget sm; as_non_null; Lget k; call rt "sget"; ret ], []) ]
                   @ fail ~kind:k_index rt (Messages.dict_absent a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 3 ], []);
        Lget 0; Test (false, T rt.recd);
        If (Bnone, [ Lget 0; Cast (false, T rt.recd); Lset rc;
                     Lget rc; struct_get rt.recd r_shape; Lget 2; struct_get rt.cache 0; ref_eq;
                     If (Bnone, [ Lget rc; struct_get rt.recd r_fields; Lget 2; struct_get rt.cache 1; array_get rt.vals; ret ], []);
                     Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 1; Lget 1; call rt "find_name"; Lset k;
                     Lget k; I32 0; i32_ge_s;
                     If (Bnone, [ Lget 2; Lget rc; struct_get rt.recd r_shape; struct_set rt.cache 0; Lget 2; Lget k; struct_set rt.cache 1;
                                  Lget rc; struct_get rt.recd r_fields; Lget k; array_get rt.vals; ret ], []) ]
                   @ fail rt (Messages.no_field a1) [ [ Lget 1 ] ] [ Lget 3 ], []);
        (* An array: the field of each of its cells. *)
        Lget 0; Test (false, T rt.list);
        If (Bnone, [ Lget 0; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; Lset n; Lget n; array_new_default rt.vals; Lset out ]
                   @ upto i n [ Lget out; Lget i; Lget l; as_non_null; Lget i; call rt "elem"; Lget 1; Lget 2; Lget 3; call rt "field"; call rt "share"; array_set rt.vals ]
                   @ [ Lget l; struct_get rt.list l_rows; Lget l; struct_get rt.list l_cols; Lget out; call rt "list_of"; ret ], []) ]
      @ fail rt (Messages.field_of a1 "\003" |> fun m -> { m with text = replace m.text [ "\003", a2 ] }) [ [ Lget 0; call rt "describe" ]; [ Lget 1 ] ] [ Lget 3 ]);
  (* m.Name = x: the map or struct to keep, the same one when owned, else a copy; a new name adds a key. *)
  def "set_field" (fun rt -> [ v; v; v; I32 ], [ v ], fun fb ->
      let mp = local fb (nl rt.map) and rc = local fb (nl rt.recd) and k = local fb I32 and n = local fb I32 and w = local fb (nn rt.vals) in
      (* A typed map written to becomes a map of the general form, owned, which the caller keeps. *)
      [ Lget 0; call rt "as_map"; Lset 0;
        Lget 0; Test (false, T rt.map);
        If (Bnone, [ Lget 0; Cast (false, T rt.map); Lset mp;
                     Lget mp; struct_get rt.map m_owned; i32_eqz; If (Bnone, [ Lget mp; as_non_null; call rt "map_copy"; Lset mp ], []);
                     Lget mp; as_non_null; Lget 1; call rt "map_find"; Lset k;
                     Lget k; I32 0; i32_ge_s;
                     If (Bnone, [ Lget mp; struct_get rt.map m_vals; Lget k; Lget 2; array_set rt.vals; Lget mp; ret ], []);
                     Lget mp; as_non_null; Lget 1; Lget 2; call rt "map_add"; Lget mp; ret ], []);
        Lget 0; Test (false, T rt.recd);
        If (Bnone, [ Lget 0; Cast (false, T rt.recd); Lset rc;
                     Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 1; Lget 1; call rt "text_of"; call rt "find_name"; Lset k;
                     Lget k; I32 0; i32_lt_s;
                     If (Bnone, fail ~kind:k_field rt (Messages.named_field "\003" a2 |> fun m -> { m with text = replace m.text [ "\003", a1 ] })
                                  [ [ Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 0 ]; [ Lget 1; call rt "text_of" ] ] [ Lget 3 ], []);
                     Lget rc; struct_get rt.recd r_owned; i32_eqz;
                     If (Bnone, [ Lget rc; struct_get rt.recd r_fields; array_len; Lset n; Lget n; array_new_default rt.vals; Lset w;
                                  Lget w; I32 0; Lget rc; struct_get rt.recd r_fields; I32 0; Lget n; array_copy rt.vals rt.vals;
                                  Lget w; Lget n; call rt "share_all";
                                  I32 1; Lget rc; struct_get rt.recd r_shape; Lget w; struct_new rt.recd; Lset rc ], []);
                     Lget rc; struct_get rt.recd r_fields; Lget k; Lget 2; array_set rt.vals; Lget rc; ret ], []) ]
      @ fail rt (Messages.field_of a1 "\003" |> fun m -> { m with text = replace m.text [ "\003", a2 ] }) [ [ Lget 0; call rt "describe" ]; [ Lget 1; call rt "text_of" ] ] [ Lget 3 ])

(* Calls: the depth, checked at each entry, and the fuel, taken at each loop and each entry. *)
let () =
  def "enter" (fun rt -> [ I32 ], [], fun _ ->
      [ Gget (depth rt); I32 1; i32_add; Gset (depth rt);
        Gget (depth rt); I32 max_depth; i32_gt_u; If (Bnone, fail ~kind:k_user rt (Messages.limit "depth") [] [ Lget 0 ], []) ]);
  (* The checkpoint: the loader says whether the fibers ready run now (at a full one) or the event loop turns. *)
  def "refuel" (fun rt -> [], [], fun fb ->
      let c = local fb I32 in
      let left = gl rt "fulls" I32 true [ I32 full_every ] in
      [ i64 fuel_period; Gset (fuel rt);
        Gget left; I32 1; i32_sub; Gset left;
        Gget left; i32_eqz; If (Bval I32, [ I32 full_every; Gset left; I32 1 ], [ I32 0 ]); host rt "checkpoint"; Ltee c;
        If (Bnone, [ Lget c; I32 (-1); call rt "park"; I32 2; i32_eq; If (Bnone, [ host rt "unwind" ], []) ], []) ])

(* The fuel of one step, inline. *)
let tick rt = [ Gget (fuel rt); i64 1; i64_sub; Gset (fuel rt); Gget (fuel rt); i64_eqz; If (Bnone, [ call rt "refuel" ], []) ]

(* The globals of a named shape, of a map literal's keys, and of a place's cache. *)
let shape rt name names =
  let g = "shape:" ^ name ^ ":" ^ String.concat "," (Array.to_list names) in
  if not (Wasm.has_global rt.m g) then begin
    let texts = Array.to_list (Array.map (fun n -> const_text rt n) names) in
    Wasm.global rt.m g (nn rt.shape) false
      ([ const_text rt name ] @ texts @ [ array_new_fixed rt.vals (Array.length names); const_text rt (Messages.article name); struct_new rt.shape ])
  end;
  Gget g

let keys rt names =
  let g = "keys:" ^ String.concat "," (Array.to_list names) in
  if not (Wasm.has_global rt.m g) then begin
    let texts = Array.to_list (Array.map (fun n -> const_text rt n) names) in
    Wasm.global rt.m g (nn rt.keys) false (texts @ [ array_new_fixed rt.vals (Array.length names); Rnull (T rt.i64s); I64 0L; struct_new rt.keys ])
  end;
  Gget g

let caches = ref 0

let cache rt =
  incr caches;
  let g = "cache" ^ string_of_int !caches in
  Wasm.global rt.m g (nn rt.cache) false [ Rnull None_; I32 0; struct_new rt.cache ];
  Gget g

(* An index of any type: a map's key, else a whole number of a list. *)
let () =
  def "index_v" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let mp = local fb (nl rt.map) and k = local fb I32 in
      [ Lget 0; Test (false, T rt.map);
        If (Bnone, [ Lget 0; Cast (false, T rt.map); Lset mp;
                     Lget mp; as_non_null; Lget 1; call rt "map_find"; Lset k;
                     Lget k; I32 0; i32_ge_s; If (Bnone, [ Lget mp; struct_get rt.map m_vals; Lget k; array_get rt.vals; call rt "share"; ret ], []) ]
                   @ fail ~kind:k_index rt (Messages.dict_absent a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ], []);
        Lget 0; Test (false, T rt.smap); Lget 1; Test (false, T rt.bytes); i32_and;
        If (Bnone, [ Lget 0; Cast (false, T rt.smap); struct_get rt.smap s_keys; struct_get rt.keys k_names; Lget 1; Cast (false, T rt.bytes); call rt "find_name"; Lset k;
                     Lget k; I32 0; i32_ge_s; If (Bnone, [ Lget 0; Cast (false, T rt.smap); Lget k; call rt "sget"; call rt "share"; ret ], []) ]
                   @ fail ~kind:k_index rt (Messages.dict_absent a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ], []);
        Lget 0; Lget 1; Lget 2; call rt "whole"; Lget 2; call rt "index" ]);
  def "set_index_v" (fun rt -> [ v; v; v; I32 ], [ v ], fun _ ->
      [ Lget 0; Test (false, T rt.map); Lget 0; Test (false, T rt.smap); Lget 1; Test (false, T rt.bytes); i32_and; i32_or;
        If (Bnone, [ Lget 0; Lget 1; Lget 2; Lget 3; call rt "set_field"; ret ], []);
        Lget 0; Lget 1; Lget 3; call rt "whole"; Lget 2; Lget 3; call rt "set_index" ])

(* Natives of std/list and std/value. *)
let () =
  (* list.Sum: floats by blocks of 65536 as Kernels.sum, integers checked, anything else by Arith.add from 0. *)
  def "sum" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let l = local fb (nl rt.list) and n = local fb I32 and i = local fb I32 and acc = local fb F64 and tot = local fb F64 in
      let ai = local fb I64 and av = local fb v and d = local fb (nl rt.f64s) and e = local fb (nl rt.i64s) in
      [ Lget 0; g_true rt; ref_eq; If (Bnone, [ I32 1; ref_i31; ret ], []);
        Lget 0; g_false rt; ref_eq; If (Bnone, [ I32 0; ref_i31; ret ], []);
        Lget 0; Test (false, T rt.list); i32_eqz; If (Bnone, [ Lget 0; ret ], []);
        Lget 0; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; Lset n;
        Lget l; struct_get rt.list l_store; Test (false, T rt.f64s);
        If (Bnone, [ Lget l; struct_get rt.list l_store; Cast (false, T rt.f64s); Lset d ]
                   @ upto i n [ Lget i; I32 0xffff; i32_and; i32_eqz;
                                If (Bnone, [ Lget tot; Lget acc; f64_add; Lset tot; F64 0.; Lset acc ], []);
                                Lget acc; Lget d; Lget i; array_get rt.f64s; f64_add; Lset acc ]
                   @ [ Lget tot; Lget acc; f64_add; call rt "box_f"; ret ], []);
        Lget l; struct_get rt.list l_store; Test (false, T rt.i64s);
        If (Bnone, [ Lget l; struct_get rt.list l_store; Cast (false, T rt.i64s); Lset e ]
                   @ upto i n [ Lget ai; Lget e; Lget i; array_get rt.i64s; Lget 1; call rt "add_i"; Lset ai ]
                   @ [ Lget ai; call rt "box_i"; ret ], []);
        I32 0; ref_i31; Lset av ]
      @ upto i n [ I32 0; Lget av; Lget l; as_non_null; Lget i; call rt "elem"; Lget 1; call rt "arith"; Lset av ]
      @ [ Lget av ]);
  (* list.Append(x, xs): in the free cell after the last when xs is the tip of its store, as Lists.push. *)
  def "append" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let l = local fb (nl rt.list) and n = local fb I32 and room = local fb I32 and w = local fb (nn rt.vals) and i = local fb I32 in
      let took = [ Lget l; I32 0; struct_set rt.list l_tip; Lget l; I32 0; struct_set rt.list l_owned;
                   I32 0; I32 1; Lget n; I32 1; i32_add; Lget l; struct_get rt.list l_store; I32 1; struct_new rt.list; ret ] in
      let fits t = [ Lget l; struct_get rt.list l_tip; Lget n; Lget l; struct_get rt.list l_store; array_len; i32_lt_u; i32_and;
                     Lget l; struct_get rt.list l_store; Test (false, T t); i32_and ] in
      [ Lget 1; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_array "Append" a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
        Lget 1; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; Lset n;
        Lget l; struct_get rt.list l_rows; I32 1; i32_eq;
        If (Bnone, [ Lget 0; Test (false, T rt.boxf) ] @ fits rt.f64s @ [ i32_and;
                     If (Bnone, [ Lget l; struct_get rt.list l_store; Cast (false, T rt.f64s); Lget n; Lget 0; call rt "float_of"; array_set rt.f64s ] @ took, []);
                     Lget 0; call rt "is_int" ] @ fits rt.i64s @ [ i32_and;
                     If (Bnone, [ Lget l; struct_get rt.list l_store; Cast (false, T rt.i64s); Lget n; Lget 0; call rt "int_of"; array_set rt.i64s ] @ took, []) ]
                   @ fits rt.vals
                   @ [ If (Bnone, [ Lget l; struct_get rt.list l_store; Cast (false, T rt.vals); Lget n; Lget 0; call rt "share"; array_set rt.vals ] @ took, []) ], []);
        (* A new store, twice as large; of values, each shared, then typed again as of_vals types it when the list is not a
           row or the kinds differ. *)
        Lget n; I32 2; i32_mul; Lset room; Lget room; I32 8; i32_lt_u; If (Bnone, [ I32 8; Lset room ], []);
        Lget room; array_new_default rt.vals; Lset w ]
      @ upto i n [ Lget w; Lget i; Lget l; as_non_null; Lget i; call rt "elem"; call rt "share"; array_set rt.vals ]
      @ [ Lget w; Lget n; Lget 0; call rt "share"; array_set rt.vals;
          I32 1; Lget n; I32 1; i32_add; Lget w; call rt "list_of"; Cast (false, T rt.list); Lset l;
          (* list_of made a store of exactly the cells, of their kind: Lists.push keeps room in a store of the same kind. *)
          Lget l; as_non_null; Lget room; call rt "with_room" ]);
  (* The same list, its store of the same kind with room for [room] cells. *)
  def "with_room" (fun rt -> [ nn rt.list; I32 ], [ v ], fun fb ->
      let n = local fb I32 and f = local fb (nn rt.f64s) and i = local fb (nn rt.i64s) and w = local fb (nn rt.vals) in
      [ Lget 0; call rt "cells"; Lset n;
        Block (Bnone, [
            Lget 0; struct_get rt.list l_store; Test (false, T rt.f64s);
            If (Bnone, [ Lget 1; array_new_default rt.f64s; Lset f; Lget f; I32 0; Lget 0; struct_get rt.list l_store; Cast (false, T rt.f64s); I32 0; Lget n; array_copy rt.f64s rt.f64s;
                         Lget 0; Lget f; struct_set rt.list l_store; Br 1 ], []);
            Lget 0; struct_get rt.list l_store; Test (false, T rt.i64s);
            If (Bnone, [ Lget 1; array_new_default rt.i64s; Lset i; Lget i; I32 0; Lget 0; struct_get rt.list l_store; Cast (false, T rt.i64s); I32 0; Lget n; array_copy rt.i64s rt.i64s;
                         Lget 0; Lget i; struct_set rt.list l_store; Br 1 ], []);
            Lget 1; array_new_default rt.vals; Lset w; Lget w; I32 0; Lget 0; struct_get rt.list l_store; Cast (false, T rt.vals); I32 0; Lget n; array_copy rt.vals rt.vals;
            Lget 0; Lget w; struct_set rt.list l_store ]);
        Lget 0 ]);
  def "concat" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let a = local fb (nl rt.list) and b = local fb (nl rt.list) and n = local fb I32 and m = local fb I32 and i = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 1; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_array "Concat" a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
        Lget 0; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_array "Concat" a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 2 ]);
        Lget 0; Cast (false, T rt.list); Lset a; Lget 1; Cast (false, T rt.list); Lset b;
        Lget a; as_non_null; call rt "cells"; Lset n; Lget b; as_non_null; call rt "cells"; Lset m;
        Lget n; Lget m; i32_add; array_new_default rt.vals; Lset w ]
      @ upto i n [ Lget w; Lget i; Lget a; as_non_null; Lget i; call rt "elem"; call rt "share"; array_set rt.vals ]
      @ upto i m [ Lget w; Lget n; Lget i; i32_add; Lget b; as_non_null; Lget i; call rt "elem"; call rt "share"; array_set rt.vals ]
      @ [ I32 1; Lget n; Lget m; i32_add; Lget w; call rt "list_of" ]);
  (* bug.Panic(x): an error of the program, its message the text of x. *)
  def "panic" (fun rt -> [ v; I32 ], [ v ], fun _ -> fail ~kind:k_user rt (Messages.plain a1) [ [ Lget 0; call rt "text_of" ] ] [ Lget 1 ])

(* list.Take, list.Skip and list.Reverse: the cells picked, a list of their kind ([Lists.picked_list]). *)
let () =
  def "count_arg" (fun rt -> [ v; I32; nn rt.bytes ], [ I32 ], fun fb ->
      let n = local fb I64 in
      [ Lget 0; Lget 1; call rt "whole"; Lset n; Lget n; i64 0; i64_lt_s;
        If (Bnone, fail rt (Messages.need_count "\003" a2 |> fun m -> { m with text = replace m.text [ "\003", a1 ] }) [ [ Lget 2 ]; [ Lget 0; call rt "describe" ] ] [ Lget 1 ], []);
        Lget n; i64 (1 lsl 30); i64_gt_s; If (Bval I32, [ I32 (1 lsl 30) ], [ Lget n; i32_wrap ]) ]);
  (* [n] cells from [from], by [step] (1 or -1). *)
  def "pick" (fun rt -> [ nn rt.list; I32; I32; I32 ], [ v ], fun fb ->
      let i = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 2; array_new_default rt.vals; Lset w ]
      @ upto i 2 [ Lget w; Lget i; Lget 0; Lget 1; Lget i; Lget 3; i32_mul; i32_add; call rt "elem"; call rt "share"; array_set rt.vals ]
      @ [ Lget 2; If (Bval I32, [ I32 1 ], [ I32 0 ]); Lget 2; Lget w; call rt "list_of" ]);
  let listed rt name x site = [ Lget x; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_array name a1) [ [ Lget x; call rt "describe" ] ] [ Lget site ]) ] in
  def "take" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let k = local fb I32 and n = local fb I32 and l = local fb (nn rt.list) in
      listed rt "Take" 1 2
      @ [ Lget 1; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n;
          Lget 0; Lget 2; text rt "Take"; call rt "count_arg"; Lset k; Lget k; Lget n; i32_gt_u; If (Bnone, [ Lget n; Lset k ], []);
          Lget l; I32 0; Lget k; I32 1; call rt "pick" ]);
  def "skip" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let k = local fb I32 and n = local fb I32 and l = local fb (nn rt.list) in
      listed rt "Skip" 1 2
      @ [ Lget 1; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n;
          Lget 0; Lget 2; text rt "Skip"; call rt "count_arg"; Lset k; Lget k; Lget n; i32_gt_u; If (Bnone, [ Lget n; Lset k ], []);
          Lget l; Lget k; Lget n; Lget k; i32_sub; I32 1; call rt "pick" ]);
  def "reverse" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let n = local fb I32 and l = local fb (nn rt.list) in
      listed rt "Reverse" 0 1
      @ [ Lget 0; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n;
          Lget l; Lget n; I32 1; i32_sub; Lget n; I32 (-1); call rt "pick" ])

(* value.Size and matrix.Reshape, of one or two dimensions. *)
let () =
  def "size" (fun rt -> [ v ], [ v ], fun fb ->
      let l = local fb (nl rt.list) in
      [ Lget 0; Test (false, T rt.list);
        If (Bnone, [ Lget 0; Cast (false, T rt.list); Lset l; I32 1; I32 1; I32 2;
                     Lget l; struct_get rt.list l_rows; ref_i31; Lget l; struct_get rt.list l_cols; ref_i31; array_new_fixed rt.vals 2;
                     I32 1; struct_new rt.list; ret ], []);
        I32 1; I32 1; I32 2; I32 1; ref_i31; I32 1; ref_i31; array_new_fixed rt.vals 2; I32 1; struct_new rt.list ]);
  def "reshape" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let s = local fb (nl rt.list) and x = local fb (nl rt.list) and r = local fb I32 and c = local fb I32 and y = local fb (nn rt.list) in
      let reshape_msg =
        let m = Messages.reshape_size 1000001 [| 1000002 |] in
        { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] }
      in
      [ Lget 0; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.reshape_shape a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 2 ]);
        Lget 0; Cast (false, T rt.list); Lset s;
        Lget s; as_non_null; call rt "cells"; i32_eqz; If (Bnone, fail rt (Messages.reshape_shape a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 2 ], []);
        Lget 1; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.index_value a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
        Lget 1; Cast (false, T rt.list); Lset x;
        Lget s; as_non_null; call rt "cells"; I32 1; i32_eq;
        If (Bnone, [ I32 1; Lset r; Lget s; as_non_null; I32 0; call rt "elem"; Lget 2; call rt "whole"; i32_wrap; Lset c ],
            [ Lget s; as_non_null; I32 0; call rt "elem"; Lget 2; call rt "whole"; i32_wrap; Lset r;
              Lget s; as_non_null; I32 1; call rt "elem"; Lget 2; call rt "whole"; i32_wrap; Lset c;
              Lget s; as_non_null; call rt "cells"; I32 2; i32_gt_u; If (Bnone, [ unreachable ], []) ]);
        Lget r; i64_extend_u; Lget c; i64_extend_u; i64_mul; Lget x; as_non_null; call rt "cells"; i64_extend_u; i64_ne;
        If (Bnone, fail rt reshape_msg [ [ Lget x; as_non_null; call rt "cells"; i64_extend_u; call rt "itoa" ];
                                         [ Lget s; as_non_null; call rt "cells"; I32 1; i32_eq;
                                           If (Bval (nn rt.bytes), [ Lget c; i64_extend_u; call rt "itoa" ],
                                               [ Lget s; as_non_null; I32 0; call rt "elem"; call rt "text_of" ]) ] ] [ Lget 2 ], []);
        Lget x; as_non_null; call rt "copy_list"; Lset y;
        Lget y; Lget r; struct_set rt.list l_rows; Lget y; Lget c; struct_set rt.list l_cols; Lget y ])

(* A container made owned on the way down a path that a write goes through: a copy when another holds it, its cells then
   held twice. *)
let () =
  def "own" (fun rt -> [ v ], [ v ], fun fb ->
      let mp = local fb (nl rt.map) and rc = local fb (nl rt.recd) and n = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 0; Test (false, T rt.list);
        If (Bnone, [ Lget 0; Cast (false, T rt.list); struct_get rt.list l_owned; If (Bnone, [ Lget 0; ret ], []);
                     Lget 0; Cast (false, T rt.list); call rt "copy_list"; ret ], []);
        Lget 0; Test (false, T rt.map);
        If (Bnone, [ Lget 0; Cast (false, T rt.map); Lset mp; Lget mp; struct_get rt.map m_owned; If (Bnone, [ Lget 0; ret ], []);
                     Lget mp; as_non_null; call rt "map_copy"; ret ], []);
        Lget 0; Test (false, T rt.smap);
        If (Bnone, [ Lget 0; Cast (false, T rt.smap); struct_get rt.smap s_owned; If (Bnone, [ Lget 0; ret ], []);
                     Lget 0; Cast (false, T rt.smap); call rt "scopy"; ret ], []);
        Lget 0; Test (false, T rt.recd);
        If (Bnone, [ Lget 0; Cast (false, T rt.recd); Lset rc; Lget rc; struct_get rt.recd r_owned; If (Bnone, [ Lget 0; ret ], []);
                     Lget rc; struct_get rt.recd r_fields; array_len; Lset n; Lget n; array_new_default rt.vals; Lset w;
                     Lget w; I32 0; Lget rc; struct_get rt.recd r_fields; I32 0; Lget n; array_copy rt.vals rt.vals; Lget w; Lget n; call rt "share_all";
                     I32 1; Lget rc; struct_get rt.recd r_shape; Lget w; struct_new rt.recd; ret ], []);
        Lget 0 ])

(* Checked integer arithmetic inline, its error out of line. An operand that is a constant, or a local read while
   nothing runs after it, is read again; another goes in a local. The sum or difference goes in the function's scratch
   local: it lives only in the check. *)
let checked rt fb op x y site =
  let pure e = match e with [ (I64 _ | Lget _) ] -> true | _ -> false in
  let keep again e = if again then [], e else let l = local fb I64 in e @ [ Lset l ], [ Lget l ] in
  let sx, a = keep (match x with [ I64 _ ] -> true | _ -> pure x && pure y) x in
  let sy, b = keep (pure y) y in
  sx @ sy
  @ (match op with
      | `Add | `Sub ->
        if fb.tmp < 0 then fb.tmp <- local fb I64;
        let r = fb.tmp in
        a @ b @ [ (if op = `Add then i64_add else i64_sub); Lset r ] @ fits63 r
        @ [ If (Bnone, [], a @ b @ site @ [ call rt (if op = `Add then "add_fail" else "sub_fail"); unreachable ]); Lget r ]
      | `Mul ->
        let small v = v @ [ i64 ((1 lsl 31) - 1); i64_add; i64 ((1 lsl 32) - 1); i64_lt_u ] in
        small a @ small b @ [ i32_and; If (Bval I64, a @ b @ [ i64_mul ], a @ b @ site @ [ call rt "mul_i" ]) ])

(* Messages.need_number of the value in the local x, with its hint when x is a function with no name, as the
   interpreter gives it. *)
let need_number rt name x site =
  let anon = "function <anonymous>" in
  [ Lget x; call rt "describe"; text rt anon; call rt "equal"; If (Bnone, fail rt (Messages.need_number name anon) [] [ Lget site ], []) ]
  @ fail rt (Messages.need_number name a1) [ [ Lget x; call rt "describe" ] ] [ Lget site ]

(* math.Round of the f64 on the stack, as OCaml's Float.round: a half goes away from zero. x - trunc x is exact. *)
let round_f fb =
  let x = local fb F64 and t = local fb F64 in
  [ Lset x; Lget x; f64_trunc; Lset t; Lget x; Lget t; f64_sub; f64_abs; F64 0.5; f64_ge;
    If (Bval F64, [ Lget t; F64 1.0; Lget x; f64_copysign; f64_add ], [ Lget t ]) ]

(* math.Floor, Ceil, Round and Abs of a value of any type, as Native's rounding and abs_value: an integer as it is (Abs
   checked), a float rounded, true 1, false 0, missing missing, an array cell by cell, else an error. *)
let () =
  List.iter
    (fun (name, key) ->
       def key (fun rt -> [ v; I32 ], [ v ], fun fb ->
           let l = local fb (nl rt.list) and i = local fb I32 and n = local fb I32 and out = local fb (nn rt.vals) in
           let float = match name with
             | "Floor" -> [ f64_floor ] | "Ceil" -> [ f64_ceil ] | "Abs" -> [ f64_abs ] | _ -> round_f fb in
           let int = if name = "Abs" then [ Lget 0; call rt "as_int"; Lget 1; call rt "abs_i"; call rt "box_i"; ret ] else [ Lget 0; ret ] in
           [ Lget 0; Test (false, T rt.boxf); If (Bnone, [ Lget 0; call rt "float_of" ] @ float @ [ call rt "box_f"; ret ], []);
             Lget 0; call rt "is_int"; If (Bnone, int, []);
             Lget 0; ref_is_null; If (Bnone, [ missing; ret ], []);
             Lget 0; g_true rt; ref_eq; If (Bnone, [ I32 1; ref_i31; ret ], []);
             Lget 0; g_false rt; ref_eq; If (Bnone, [ I32 0; ref_i31; ret ], []);
             Lget 0; Test (false, T rt.list);
             If (Bnone, [ Lget 0; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; Lset n; Lget n; array_new_default rt.vals; Lset out ]
                        @ upto i n [ Lget out; Lget i; Lget l; as_non_null; Lget i; call rt "elem"; Lget 1; call rt key; array_set rt.vals ]
                        @ [ Lget l; struct_get rt.list l_rows; Lget l; struct_get rt.list l_cols; Lget out; call rt "list_of"; ret ], []) ]
           @ need_number rt name 0 1))
    [ "Floor", "floor_v"; "Ceil", "ceil_v"; "Round", "round_v"; "Abs", "abs_v" ];
  def "abs_i" (fun rt -> [ I64; I32 ], [ I64 ], fun _ ->
      [ Lget 0; i64 0; i64_lt_s; If (Bval I64, [ Lget 0; Lget 1; call rt "neg_i" ], [ Lget 0 ]) ])

(* Fibers and channels: std/fiber, as Fiber of the interpreter, on the loader's scheduler. *)

let i32_rem_u = Op 0x70
let i32_and1 = [ I32 1; i32_and ]

(* The records of std/result and the errors of a wait: result.Ok(x), result.Err(x), and Err({Kind, Message}). *)
let ok_of rt x = [ I32 1; shape rt "Ok" [| "Value" |] ] @ x @ [ call rt "share"; array_new_fixed rt.vals 1; struct_new rt.recd ]
let err_of rt x = [ I32 1; shape rt "Err" [| "Error" |] ] @ x @ [ call rt "share"; array_new_fixed rt.vals 1; struct_new rt.recd ]
let failure rt kind (m : Messages.t) =
  err_of rt [ I32 1; keys rt [| "Kind"; "Message" |]; text rt kind; text rt m.text; array_new_fixed rt.vals 2; I32 2; I32 0; struct_new rt.map ]

let current rt = gl rt "current" (nl rt.fib) true [ Rnull (T rt.fib) ]
let got rt = gl rt "got" I32 true [ I32 0 ]
let next_id rt = gl rt "next_id" I32 true [ I32 1 ]

(* Queues. *)
let q_arr = 0
let q_head = 1
let q_n = 2

let () =
  def "q_new" (fun rt -> [], [ nn rt.q ], fun _ -> [ I32 4; array_new_default rt.vals; I32 0; I32 0; struct_new rt.q ]);
  def "q_grow" (fun rt -> [ nn rt.q ], [], fun fb ->
      let a = local fb (nn rt.vals) and w = local fb (nn rt.vals) and n = local fb I32 and i = local fb I32 in
      [ Lget 0; struct_get rt.q q_arr; Lset a; Lget a; array_len; Lset n; Lget n; I32 2; i32_mul; array_new_default rt.vals; Lset w ]
      @ upto i n [ Lget w; Lget i; Lget a; Lget 0; struct_get rt.q q_head; Lget i; i32_add; Lget n; i32_rem_u; array_get rt.vals; array_set rt.vals ]
      @ [ Lget 0; Lget w; struct_set rt.q q_arr; Lget 0; I32 0; struct_set rt.q q_head ]);
  def "q_push" (fun rt -> [ nn rt.q; v ], [], fun _ ->
      [ Lget 0; struct_get rt.q q_n; Lget 0; struct_get rt.q q_arr; array_len; i32_eq; If (Bnone, [ Lget 0; call rt "q_grow" ], []);
        Lget 0; struct_get rt.q q_arr;
        Lget 0; struct_get rt.q q_head; Lget 0; struct_get rt.q q_n; i32_add; Lget 0; struct_get rt.q q_arr; array_len; i32_rem_u;
        Lget 1; array_set rt.vals;
        Lget 0; Lget 0; struct_get rt.q q_n; I32 1; i32_add; struct_set rt.q q_n ]);
  (* At the front: a receiver woken for a value another took waits first again. *)
  def "q_front" (fun rt -> [ nn rt.q; v ], [], fun _ ->
      [ Lget 0; struct_get rt.q q_n; Lget 0; struct_get rt.q q_arr; array_len; i32_eq; If (Bnone, [ Lget 0; call rt "q_grow" ], []);
        Lget 0; Lget 0; struct_get rt.q q_head; Lget 0; struct_get rt.q q_arr; array_len; i32_add; I32 1; i32_sub;
        Lget 0; struct_get rt.q q_arr; array_len; i32_rem_u; struct_set rt.q q_head;
        Lget 0; struct_get rt.q q_arr; Lget 0; struct_get rt.q q_head; Lget 1; array_set rt.vals;
        Lget 0; Lget 0; struct_get rt.q q_n; I32 1; i32_add; struct_set rt.q q_n ]);
  (* The first, taken out; missing when empty. *)
  def "q_shift" (fun rt -> [ nn rt.q ], [ v ], fun fb ->
      let x = local fb v in
      [ Lget 0; struct_get rt.q q_n; i32_eqz; If (Bnone, [ missing; ret ], []);
        Lget 0; struct_get rt.q q_arr; Lget 0; struct_get rt.q q_head; array_get rt.vals; Lset x;
        Lget 0; struct_get rt.q q_arr; Lget 0; struct_get rt.q q_head; missing; array_set rt.vals;
        Lget 0; Lget 0; struct_get rt.q q_head; I32 1; i32_add; Lget 0; struct_get rt.q q_arr; array_len; i32_rem_u; struct_set rt.q q_head;
        Lget 0; Lget 0; struct_get rt.q q_n; I32 1; i32_sub; struct_set rt.q q_n; Lget x ]);
  (* Takes this one out, the others in their order. *)
  def "q_drop" (fun rt -> [ nn rt.q; v ], [], fun fb ->
      let i = local fb I32 and n = local fb I32 and y = local fb v in
      [ Lget 0; struct_get rt.q q_n; Lset n ]
      @ upto i n [ Lget 0; call rt "q_shift"; Lset y; Lget y; Lget 1; ref_eq; If (Bnone, [], [ Lget 0; Lget y; call rt "q_push" ]) ])

(* Fields. *)
let fb_parks = 0
let fb_cancelled = 1
let fb_late = 2
let fb_depth = 3
let fb_calls = 4
let fb_task = 5
let fb_site = 6
let c_items = 0
let c_size = 1
let c_receivers = 2
let c_senders = 3
let c_closed = 4
let c_id = 5
let t_done = 0
let t_result = 1
let t_waiters = 2
let t_fib = 3
let t_id = 4

let () =
  (* The fiber that runs: the main program's, made at the first need. *)
  def "cur" (fun rt -> [], [ nn rt.fib ], fun fb ->
      let f = local fb (nn rt.fib) in
      [ Gget (current rt); ref_is_null;
        If (Bnone, [ I32 0; I32 0; I32 0; I32 0; Rnull (T rt.i32s); missing; I32 (-1); struct_new rt.fib; Lset f;
                     Lget f; Gset (current rt); Lget f; host rt "first" ], []);
        Gget (current rt); as_non_null ]);
  (* Wakes the fiber of a wake still current: 1 if it did. *)
  def "try_wake" (fun rt -> [ v ], [ I32 ], fun fb ->
      let t = local fb (nn rt.tok) and f = local fb (nn rt.fib) in
      [ Lget 0; Cast (false, T rt.tok); Lset t; Lget t; struct_get rt.tok 0; Lset f;
        Lget f; struct_get rt.fib fb_parks; Lget t; struct_get rt.tok 1; i32_eq;
        If (Bval I32, [ Lget f; Lget t; struct_get rt.tok 1; I32 1; i32_add; struct_set rt.fib fb_parks; Lget f; host rt "wake"; I32 1 ], [ I32 0 ]) ]);
  (* Wakes a fiber wherever it waits: a cancel, a timer. *)
  def "wake_fib" (fun rt -> [ nn rt.fib ], [], fun _ ->
      [ Lget 0; struct_get rt.fib fb_parks ] @ i32_and1
      @ [ If (Bnone, [ Lget 0; Lget 0; struct_get rt.fib fb_parks; I32 1; i32_add; struct_set rt.fib fb_parks; Lget 0; host rt "wake" ], []) ]);
  (* The wake of the park about to be: the parks of the current fiber, odd now. *)
  def "begin_park" (fun rt -> [], [ nn rt.tok ], fun fb ->
      let f = local fb (nn rt.fib) in
      [ call rt "cur"; Lset f; Lget f; Lget f; struct_get rt.fib fb_parks; I32 1; i32_add; struct_set rt.fib fb_parks;
        Lget f; Lget f; struct_get rt.fib fb_parks; struct_new rt.tok ]);
  (* Parks the current fiber, mode 0 until a wake, 1 behind the fibers ready, 2 until the event loop turned: its depth and
     call sites kept and put back. 2 when it was cancelled; a deadlock is the error of the main program at [site]. *)
  def "park" (fun rt -> [ I32; I32 ], [ I32 ], fun fb ->
      let f = local fb (nn rt.fib) and n = local fb I32 and i = local fb I32 and c = local fb (nn rt.i32s) and code = local fb I32 in
      [ call rt "cur"; Lset f;
        Gget (depth rt); I32 2; i32_add; Lset n;
        Lget f; struct_get rt.fib fb_calls; ref_is_null;
        If (Bval I32, [ I32 1 ], [ Lget f; struct_get rt.fib fb_calls; as_non_null; array_len; Lget n; i32_lt_u ]);
        If (Bnone, [ Lget f; Lget n; I32 16; i32_add; array_new_default rt.i32s; struct_set rt.fib fb_calls ], []);
        Lget f; struct_get rt.fib fb_calls; as_non_null; Lset c ]
      @ upto i n [ Lget c; Lget i; Lget i; I32 4; i32_mul; load32 calls; array_set rt.i32s ]
      @ [ Lget f; Gget (depth rt); struct_set rt.fib fb_depth;
          Lget f; Lget 0; host rt "park"; Lset code;
          Lget f; Gset (current rt); Lget f; struct_get rt.fib fb_depth; Gset (depth rt);
          Lget f; struct_get rt.fib fb_calls; as_non_null; Lset c ]
      @ upto i n [ Lget i; I32 4; i32_mul; Lget c; Lget i; array_get rt.i32s; store32 calls ]
      @ [ Lget code; I32 1; i32_eq; If (Bnone, fail ~kind:k_user rt Messages.deadlock [] [ Lget 1 ], []);
          Lget f; struct_get rt.fib fb_cancelled; If (Bval I32, [ I32 2 ], [ I32 0 ]) ]);
  (* A timeout or a wait in seconds: -1 for none. *)
  def "seconds" (fun rt -> [ v; I32 ], [ F64 ], fun fb ->
      let x = local fb F64 in
      [ Lget 0; ref_is_null; Lget 0; g_undef rt; ref_eq; i32_or; If (Bnone, [ F64 (-1.); ret ], []);
        Lget 0; call rt "is_int"; If (Bnone, [ Lget 0; call rt "int_of"; i64 0; i64_ge_s; If (Bnone, [ Lget 0; call rt "int_of"; f64_of_i64; ret ], []) ], []);
        Lget 0; Test (false, T rt.boxf); If (Bnone, [ Lget 0; call rt "float_of"; Ltee x; F64 0.; f64_ge; If (Bnone, [ Lget x; ret ], []) ], []) ]
      @ fail rt (Messages.bad_timeout a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
  (* sys.Sleep's seconds, as Proc.seconds: at least 0, finite, at most a day of seconds... as the interpreter's max_sleep. *)
  def "duration" (fun rt -> [ v; I32 ], [ F64 ], fun fb ->
      let x = local fb F64 in
      [ Lget 0; call rt "is_int"; If (Bnone, [ Lget 0; call rt "int_of"; i64 0; i64_ge_s; If (Bnone, [ Lget 0; call rt "int_of"; f64_of_i64; ret ], []) ], []);
        Lget 0; Test (false, T rt.boxf);
        If (Bnone, [ Lget 0; call rt "float_of"; Ltee x; F64 0.; f64_ge; Lget x; F64 infinity; f64_lt; i32_and; If (Bnone, [ Lget x; ret ], []) ], []) ]
      @ fail rt (Messages.bad_duration "Sleep" a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ])

(* Channels. *)
let () =
  def "chan_make" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let size = local fb I32 in
      [ I32 0x7fffffff; Lset size;
        Lget 0; ref_is_null; Lget 0; g_undef rt; ref_eq; i32_or;
        If (Bnone, [], [ Lget 0; call rt "is_int"; If (Bval I32, [ Lget 0; call rt "int_of"; i64 0; i64_ge_s ], [ I32 0 ]);
                         If (Bnone, [ Lget 0; call rt "int_of"; i64 0x7fffffff; i64_lt_s;
                                      If (Bval I32, [ Lget 0; call rt "int_of"; i32_wrap ], [ I32 0x7fffffff ]); Lset size ],
                             fail rt (Messages.channel_size a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]) ]);
        call rt "q_new"; Lget size; call rt "q_new"; call rt "q_new"; I32 0; Gget (next_id rt); struct_new rt.chan;
        Gget (next_id rt); I32 1; i32_add; Gset (next_id rt) ]);
  let check name ty need =
    def ("as_" ^ name) (fun rt -> [ v; nn rt.bytes; I32 ], [ nn (ty rt) ], fun _ ->
        [ Lget 0; Test (false, T (ty rt)); If (Bnone, [ Lget 0; Cast (false, T (ty rt)); ret ], []) ]
        @ fail rt (need "\003" a2 |> fun (m : Messages.t) -> { m with text = replace m.text [ "\003", a1 ] }) [ [ Lget 1 ]; [ Lget 0; call rt "describe" ] ] [ Lget 2 ])
  in
  check "chan" (fun rt -> rt.chan) Messages.need_channel;
  check "task" (fun rt -> rt.task) Messages.need_task;
  (* The oldest sender still waiting, which goes on its way, or none. *)
  def "from_sender" (fun rt -> [ nn rt.chan ], [ nl rt.sender ], fun fb ->
      let s = local fb v in
      [ Loop (Bnone, [
            Lget 0; struct_get rt.chan c_senders; call rt "q_shift"; Lset s;
            Lget s; ref_is_null; If (Bnone, [ Rnull (T rt.sender); ret ], []);
            Lget s; Cast (false, T rt.sender); struct_get rt.sender 1; call rt "try_wake";
            If (Bnone, [ Lget s; Cast (false, T rt.sender); I32 1; struct_set rt.sender 2; Lget s; Cast (true, T rt.sender); ret ], []);
            Br 0 ]);
        unreachable ]);
  (* The oldest value of a channel, [got] 1; or [got] 0. A full channel takes in the value of its oldest sender. *)
  def "next" (fun rt -> [ nn rt.chan ], [ v ], fun fb ->
      let x = local fb v and s = local fb (nl rt.sender) in
      [ I32 1; Gset (got rt);
        Lget 0; struct_get rt.chan c_items; struct_get rt.q q_n;
        If (Bnone, [ Lget 0; struct_get rt.chan c_items; call rt "q_shift"; Lset x;
                     Lget 0; struct_get rt.chan c_senders; struct_get rt.q q_n;
                     If (Bnone, [ Lget 0; call rt "from_sender"; Lset s;
                                  Lget s; ref_is_null; If (Bnone, [], [ Lget 0; struct_get rt.chan c_items; Lget s; struct_get rt.sender 0; call rt "q_push" ]) ], []);
                     Lget x; ret ], []);
        Lget 0; call rt "from_sender"; Lset s;
        Lget s; ref_is_null; If (Bnone, [], [ Lget s; struct_get rt.sender 0; ret ]);
        I32 0; Gset (got rt); missing ]);
  def "has_value" (fun rt -> [ nn rt.chan ], [ I32 ], fun _ ->
      [ Lget 0; struct_get rt.chan c_items; struct_get rt.q q_n; Lget 0; struct_get rt.chan c_senders; struct_get rt.q q_n; i32_or ]);
  def "wake_receiver" (fun rt -> [ nn rt.chan ], [], fun fb ->
      let t = local fb v in
      [ Loop (Bnone, [
            Lget 0; struct_get rt.chan c_receivers; call rt "q_shift"; Lset t;
            Lget t; ref_is_null; If (Bnone, [ ret ], []);
            Lget t; call rt "try_wake"; If (Bnone, [ ret ], []);
            Br 0 ]) ]);
  (* fiber.Receive: an Ok of the oldest value, waiting at most [timeout] seconds for one. *)
  def "receive" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let ch = local fb (nn rt.chan) and secs = local fb F64 and x = local fb v and f = local fb (nn rt.fib) in
      let timer = local fb I32 and t = local fb (nn rt.tok) and again = local fb I32 and code = local fb I32 in
      let untimer = [ Lget timer; I32 0; i32_ge_s; If (Bnone, [ Lget timer; host rt "untimer" ], []) ] in
      [ Lget 0; text rt "Receive"; Lget 2; call rt "as_chan"; Lset ch;
        Lget 1; Lget 2; call rt "seconds"; Lset secs;
        Lget ch; call rt "next"; Lset x; Gget (got rt); If (Bnone, ok_of rt [ Lget x ] @ [ ret ], []);
        Lget ch; struct_get rt.chan c_closed; If (Bnone, failure rt "closed" Messages.channel_closed @ [ ret ], []);
        Lget secs; F64 0.; f64_eq; If (Bnone, failure rt "timeout" Messages.receive_timeout @ [ ret ], []);
        call rt "cur"; Lset f; Lget f; I32 0; struct_set rt.fib fb_late; I32 (-1); Lset timer;
        Lget secs; F64 0.; f64_gt; If (Bnone, [ Lget f; Lget secs; host rt "timer"; Lset timer ], []);
        Loop (Bnone, [
            call rt "begin_park"; Lset t;
            Lget again; If (Bnone, [ Lget ch; struct_get rt.chan c_receivers; Lget t; call rt "q_front" ], [ Lget ch; struct_get rt.chan c_receivers; Lget t; call rt "q_push" ]);
            I32 0; Lget 2; call rt "park"; Lset code;
            Lget code; I32 2; i32_eq;
            If (Bnone, [ Lget ch; struct_get rt.chan c_receivers; Lget t; call rt "q_drop" ] @ untimer
                       @ [ Lget ch; call rt "has_value"; If (Bnone, [ Lget ch; call rt "wake_receiver" ], []); host rt "unwind" ], []);
            Lget ch; call rt "next"; Lset x; Gget (got rt); If (Bnone, untimer @ ok_of rt [ Lget x ] @ [ ret ], []);
            Lget ch; struct_get rt.chan c_closed; If (Bnone, untimer @ failure rt "closed" Messages.channel_closed @ [ ret ], []);
            Lget f; struct_get rt.fib fb_late;
            If (Bnone, [ Lget ch; struct_get rt.chan c_receivers; Lget t; call rt "q_drop" ] @ failure rt "timeout" Messages.receive_timeout @ [ ret ], []);
            I32 1; Lset again; Br 0 ]);
        unreachable ]);
  (* fiber.Send: at the end of the channel; on one full, it waits for a receiver to take it. *)
  def "chan_send" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let ch = local fb (nn rt.chan) and x = local fb v and s = local fb (nn rt.sender) and code = local fb I32 in
      [ Lget 1; text rt "Send"; Lget 2; call rt "as_chan"; Lset ch;
        Lget ch; struct_get rt.chan c_closed; If (Bnone, fail ~kind:k_user rt Messages.send_closed [] [ Lget 2 ], []);
        Lget 0; call rt "share"; Lset x;
        Lget ch; struct_get rt.chan c_items; struct_get rt.q q_n; Lget ch; struct_get rt.chan c_size; i32_lt_u;
        If (Bnone, [ Lget ch; struct_get rt.chan c_items; Lget x; call rt "q_push"; Lget ch; call rt "wake_receiver"; missing; ret ], []);
        Lget x; call rt "begin_park"; I32 0; struct_new rt.sender; Lset s;
        Lget ch; struct_get rt.chan c_senders; Lget s; call rt "q_push"; Lget ch; call rt "wake_receiver";
        I32 0; Lget 2; call rt "park"; Lset code;
        Lget code; I32 2; i32_eq;
        If (Bnone, [ Lget s; struct_get rt.sender 2; i32_eqz; If (Bnone, [ Lget ch; struct_get rt.chan c_senders; Lget s; call rt "q_drop" ], []); host rt "unwind" ], []);
        Lget s; struct_get rt.sender 2; If (Bnone, [ missing; ret ], []) ]
      @ fail ~kind:k_user rt Messages.send_closed [] [ Lget 2 ]);
  (* Closes a channel: its receivers wake to what is left, its senders find it closed. *)
  def "close_chan" (fun rt -> [ nn rt.chan ], [], fun fb ->
      let t = local fb v in
      [ Lget 0; I32 1; struct_set rt.chan c_closed;
        Block (Bnone, [ Loop (Bnone, [ Lget 0; struct_get rt.chan c_receivers; call rt "q_shift"; Lset t; Lget t; ref_is_null; Br_if 1;
                                       Lget t; call rt "try_wake"; drop; Br 0 ]) ]);
        Block (Bnone, [ Loop (Bnone, [ Lget 0; struct_get rt.chan c_senders; call rt "q_shift"; Lset t; Lget t; ref_is_null; Br_if 1;
                                       Lget t; Cast (false, T rt.sender); struct_get rt.sender 1; call rt "try_wake"; drop; Br 0 ]) ]) ]);
  def "close" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let ch = local fb (nn rt.chan) in
      [ Lget 0; text rt "Close"; Lget 1; call rt "as_chan"; Lset ch;
        Lget ch; struct_get rt.chan c_closed; If (Bnone, fail ~kind:k_user rt Messages.closed_twice [] [ Lget 1 ], []);
        Lget ch; call rt "close_chan"; missing ]);
  (* From JavaScript: a value put in a channel, past its size if need be (1), or none to a closed one (0); a close. *)
  def "x_post" (fun rt -> [ v; v ], [ I32 ], fun fb ->
      let ch = local fb (nn rt.chan) in
      [ Lget 0; Cast (false, T rt.chan); Lset ch; Lget ch; struct_get rt.chan c_closed; If (Bnone, [ I32 0; ret ], []);
        Lget ch; struct_get rt.chan c_items; Lget 1; call rt "q_push"; Lget ch; call rt "wake_receiver"; I32 1 ]);
  def "x_shut" (fun rt -> [ v ], [], fun fb ->
      let ch = local fb (nn rt.chan) in
      [ Lget 0; Cast (false, T rt.chan); Lset ch; Lget ch; struct_get rt.chan c_closed; If (Bnone, [ ret ], []); Lget ch; call rt "close_chan" ])

(* Tasks. *)
let panic_keys = [| "Message"; "Kind"; "File"; "Line" |]

let () =
  (* fiber.Spawn: the task of f(), which starts once the fibers before it parked. *)
  def "spawn" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let t = local fb (nn rt.task) and f = local fb (nn rt.fib) in
      [ Lget 0; Test (false, T rt.fn); If (Bnone, [], fail rt (Messages.not_function a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
        I32 0; missing; call rt "q_new"; Rnull (T rt.fib); Gget (next_id rt); struct_new rt.task; Lset t;
        Gget (next_id rt); I32 1; i32_add; Gset (next_id rt);
        I32 0; I32 0; I32 0; I32 0; Rnull (T rt.i32s); Lget t; Lget 1; struct_new rt.fib; Lset f;
        Lget t; Lget f; struct_set rt.task t_fib;
        Lget f; Lget 0; Cast (false, T rt.fn); Lget 1; host rt "spawn"; Lget t ]);
  (* The end of a task: its result, its waiters woken. *)
  def "finish" (fun rt -> [ nn rt.task; v ], [], fun fb ->
      let w = local fb v in
      [ Lget 0; Lget 1; struct_set rt.task t_result; Lget 0; I32 1; struct_set rt.task t_done; Lget 0; Rnull (T rt.fib); struct_set rt.task t_fib;
        Block (Bnone, [ Loop (Bnone, [ Lget 0; struct_get rt.task t_waiters; call rt "q_shift"; Lset w; Lget w; ref_is_null; Br_if 1;
                                       Lget w; call rt "try_wake"; drop; Br 0 ]) ]) ]);
  (* From the loader: a fiber stopped by a panic (its message) or a cancel (none): the Err of its task. *)
  def "x_ended" (fun rt -> [ nn rt.fib; v; v; v; I32 ], [], fun _ ->
      [ Lget 0; struct_get rt.fib fb_task; Cast (false, T rt.task) ]
      @ err_of rt [ I32 1; keys rt panic_keys;
                    Lget 1; ref_is_null; If (Bval v, [ text rt Messages.cancelled.text ], [ Lget 1 ]);
                    Lget 2; Lget 3; Lget 4; i64_extend_s; call rt "box_i"; array_new_fixed rt.vals 4; I32 4; I32 0; struct_new rt.map ]
      @ [ call rt "finish" ]);
  (* fiber.Wait: the result of a task once it ended, waiting at most [timeout] seconds. *)
  def "wait" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let t = local fb (nn rt.task) and secs = local fb F64 and f = local fb (nn rt.fib) and k = local fb (nn rt.tok) in
      let timer = local fb I32 and code = local fb I32 in
      [ Lget 0; text rt "Wait"; Lget 2; call rt "as_task"; Lset t;
        Lget 1; Lget 2; call rt "seconds"; Lset secs;
        Lget t; struct_get rt.task t_done; If (Bnone, [ Lget t; struct_get rt.task t_result; call rt "share"; ret ], []);
        Lget secs; F64 0.; f64_eq; If (Bnone, failure rt "timeout" Messages.wait_timeout @ [ ret ], []);
        call rt "cur"; Lset f; Lget f; I32 0; struct_set rt.fib fb_late; I32 (-1); Lset timer;
        call rt "begin_park"; Lset k; Lget t; struct_get rt.task t_waiters; Lget k; call rt "q_push";
        Lget secs; F64 0.; f64_gt; If (Bnone, [ Lget f; Lget secs; host rt "timer"; Lset timer ], []);
        I32 0; Lget 2; call rt "park"; Lset code;
        Lget timer; I32 0; i32_ge_s; If (Bnone, [ Lget timer; host rt "untimer" ], []);
        Lget code; I32 2; i32_eq; If (Bnone, [ Lget t; struct_get rt.task t_waiters; Lget k; call rt "q_drop"; host rt "unwind" ], []);
        Lget t; struct_get rt.task t_done; If (Bnone, [ Lget t; struct_get rt.task t_result; call rt "share"; ret ], []);
        Lget t; struct_get rt.task t_waiters; Lget k; call rt "q_drop" ]
      @ failure rt "timeout" Messages.wait_timeout);
  (* fiber.Cancel: the fiber stops at its next wait, at once when it is the one that runs. *)
  def "cancel" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let f = local fb (nl rt.fib) in
      [ Lget 0; text rt "Cancel"; Lget 1; call rt "as_task"; struct_get rt.task t_fib; Lset f;
        Lget f; ref_is_null; If (Bnone, [ missing; ret ], []);
        Lget f; struct_get rt.fib fb_cancelled; If (Bnone, [ missing; ret ], []);
        Lget f; I32 1; struct_set rt.fib fb_cancelled;
        Lget f; Gget (current rt); ref_eq; If (Bnone, [ host rt "unwind" ], []);
        Lget f; as_non_null; call rt "wake_fib"; missing ]);
  (* From the loader: the timer of a wait ran out. *)
  def "x_timeout" (fun rt -> [ nn rt.fib ], [], fun _ ->
      [ Lget 0; struct_get rt.fib fb_parks ] @ i32_and1 @ [ If (Bnone, [ Lget 0; I32 1; struct_set rt.fib fb_late; Lget 0; call rt "wake_fib" ], []) ]);
  (* sys.Sleep: 0 lets the fibers ready run first. *)
  def "sleep" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let secs = local fb F64 and f = local fb (nn rt.fib) and timer = local fb I32 in
      [ Lget 0; Lget 1; call rt "duration"; Lset secs;
        Lget secs; F64 0.; f64_le;
        If (Bnone, [ I32 1; Lget 1; call rt "park"; I32 2; i32_eq; If (Bnone, [ host rt "unwind" ], []); missing; ret ], []);
        call rt "cur"; Lset f; call rt "begin_park"; drop;
        Lget f; Lget secs; host rt "timer"; Lset timer;
        I32 0; Lget 1; call rt "park"; I32 2; i32_eq; If (Bnone, [ Lget timer; host rt "untimer"; host rt "unwind" ], []);
        missing ]);
  def "now" (fun rt -> [], [ v ], fun _ -> [ host rt "now"; call rt "box_f" ])

(* Values to JavaScript and back, for the loader: what a value is (0 missing, 1 an integer, 2 a float, 3 a boolean, 4 a text,
   5 a list, 6 a channel, 7 anything else), its number, the bytes of a text through the second page, a list's cells; a
   text, a number (an integer when it is one), a boolean and a list made from JavaScript. *)
let () =
  def "x_kind" (fun rt -> [ v ], [ I32 ], fun _ ->
      [ Lget 0; ref_is_null; If (Bnone, [ I32 0; ret ], []);
        Lget 0; call rt "is_int"; If (Bnone, [ I32 1; ret ], []);
        Lget 0; Test (false, T rt.boxf); If (Bnone, [ I32 2; ret ], []);
        Lget 0; g_true rt; ref_eq; Lget 0; g_false rt; ref_eq; i32_or; If (Bnone, [ I32 3; ret ], []);
        Lget 0; Test (false, T rt.bytes); If (Bnone, [ I32 4; ret ], []);
        Lget 0; Test (false, T rt.list); If (Bnone, [ I32 5; ret ], []);
        Lget 0; Test (false, T rt.chan); If (Bval I32, [ I32 6 ], [ I32 7 ]) ]);
  def "x_num" (fun rt -> [ v ], [ F64 ], fun _ ->
      [ Lget 0; g_true rt; ref_eq; If (Bnone, [ F64 1.; ret ], []); Lget 0; g_false rt; ref_eq; If (Bnone, [ F64 0.; ret ], []);
        Lget 0; call rt "as_float" ]);
  def "x_size" (fun rt -> [ v ], [ I32 ], fun _ -> [ Lget 0; Cast (false, T rt.bytes); array_len ]);
  def "x_bytes" (fun rt -> [ v; I32; I32 ], [], fun fb ->
      let b = local fb (nn rt.bytes) and i = local fb I32 in
      [ Lget 0; Cast (false, T rt.bytes); Lset b ]
      @ upto i 2 [ Lget i; Lget b; Lget 1; Lget i; i32_add; array_get_u rt.bytes; store8 window ]);
  def "x_count" (fun rt -> [ v ], [ I32 ], fun _ -> [ Lget 0; Cast (false, T rt.list); call rt "cells" ]);
  def "x_item" (fun rt -> [ v; I32 ], [ v ], fun _ -> [ Lget 0; Cast (false, T rt.list); Lget 1; call rt "elem" ]);
  def "x_text" (fun rt -> [ I32 ], [ v ], fun _ -> [ Lget 0; array_new_default rt.bytes ]);
  def "x_fill" (fun rt -> [ v; I32; I32 ], [], fun fb ->
      let b = local fb (nn rt.bytes) and i = local fb I32 in
      [ Lget 0; Cast (false, T rt.bytes); Lset b ]
      @ upto i 2 [ Lget b; Lget 1; Lget i; i32_add; Lget i; load8 window; array_set rt.bytes ]);
  def "x_number" (fun rt -> [ F64 ], [ v ], fun _ ->
      [ Lget 0; f64_trunc; Lget 0; f64_eq; Lget 0; f64_abs; F64 9007199254740992.; f64_le; i32_and;
        If (Bval v, [ Lget 0; i64_trunc_sat; call rt "box_i" ], [ Lget 0; call rt "box_f" ]) ]);
  def "x_boolean" (fun rt -> [ I32 ], [ v ], fun _ -> [ Lget 0; If (Bval v, [ g_true rt ], [ g_false rt ]) ]);
  def "x_list" (fun rt -> [ I32 ], [ v ], fun _ -> [ Lget 0; array_new_default rt.vals ]);
  def "x_put" (fun rt -> [ v; I32; v ], [], fun _ -> [ Lget 0; Cast (false, T rt.vals); Lget 1; Lget 2; array_set rt.vals ]);
  def "x_listed" (fun rt -> [ v ], [ v ], fun fb ->
      let a = local fb (nn rt.vals) in
      [ Lget 0; Cast (false, T rt.vals); Lset a; I32 1; Lget a; array_len; Lget a; call rt "list_of" ])

(* The exports that the loader calls: [flush] always; for fibers and js.Call, the ones of their values. *)
let export_all rt names = List.iter (fun n -> if not (List.exists (fun (e, _) -> e = n) (Vec.to_list rt.m.exports)) then Wasm.export rt.m n (need rt ("x_" ^ n))) names
let for_js rt = export_all rt [ "kind"; "num"; "size"; "bytes"; "count"; "item"; "text"; "fill"; "number"; "boolean"; "list"; "put"; "listed"; "post"; "shut" ]
let for_fibers rt = export_all rt [ "text"; "fill"; "ended"; "timeout" ]

(* fiber.Select: the first channel of the list with a value, or closed and empty, in the order of the list; else the
   fiber waits on all of them, with one timer for the whole wait, and looks again when woken. *)
let () =
  def "select" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let l = local fb (nn rt.list) and n = local fb I32 and i = local fb I32 and j = local fb I32 and ch = local fb (nn rt.chan) in
      let x = local fb v and secs = local fb F64 and f = local fb (nn rt.fib) and timer = local fb I32 and t = local fb (nn rt.tok) in
      let again = local fb I32 and code = local fb I32 and h = local fb v in
      let nth k = [ Lget l; Lget k; call rt "elem" ] in
      let untimer = [ Lget timer; I32 0; i32_ge_s; If (Bnone, [ Lget timer; host rt "untimer" ], []) ] in
      let leave = upto j n (nth j @ [ Cast (false, T rt.chan); struct_get rt.chan c_receivers; Lget t; call rt "q_drop" ]) in
      (* The first ready: Ok({Channel, Value}) or Err({Kind: "closed", Message, Channel}); the others with a value wake
         their next receiver. *)
      let first =
        upto i n (nth i @ [ Lset h; Lget h; Cast (false, T rt.chan); Lset ch; Lget ch; call rt "next"; Lset x;
                            Gget (got rt); Lget ch; struct_get rt.chan c_closed; i32_or;
                            If (Bnone, untimer
                                       @ upto j n ([ Lget j; Lget i; i32_ne ] @ nth j @ [ Cast (false, T rt.chan); call rt "has_value"; i32_and;
                                                   If (Bnone, nth j @ [ Cast (false, T rt.chan); call rt "wake_receiver" ], []) ])
                                       @ [ Gget (got rt);
                                           If (Bval v, ok_of rt [ I32 1; keys rt [| "Channel"; "Value" |]; Lget h; Lget x; array_new_fixed rt.vals 2; I32 2; I32 0; struct_new rt.map ],
                                               err_of rt [ I32 1; keys rt [| "Kind"; "Message"; "Channel" |]; text rt "closed"; text rt Messages.channel_closed.text; Lget h;
                                                           array_new_fixed rt.vals 3; I32 3; I32 0; struct_new rt.map ]); ret ], []) ])
      in
      [ Lget 0; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_channels a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 2 ]);
        Lget 0; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n ]
      @ upto i n (nth i @ [ text rt "Select"; Lget 2; call rt "as_chan"; drop ])
      @ [ Lget 1; Lget 2; call rt "seconds"; Lset secs; I32 (-1); Lset timer ]
      @ first
      @ [ Lget secs; F64 0.; f64_eq; If (Bnone, failure rt "timeout" Messages.select_timeout @ [ ret ], []);
          call rt "cur"; Lset f; Lget f; I32 0; struct_set rt.fib fb_late;
          Lget secs; F64 0.; f64_gt; If (Bnone, [ Lget f; Lget secs; host rt "timer"; Lset timer ], []);
          Loop (Bnone, [ call rt "begin_park"; Lset t ]
                       @ upto j n (let q = nth j @ [ Cast (false, T rt.chan); struct_get rt.chan c_receivers; Lget t ] in
                                   [ Lget again; If (Bnone, q @ [ call rt "q_front" ], q @ [ call rt "q_push" ]) ])
                       @ [ I32 0; Lget 2; call rt "park"; Lset code ]
                       @ leave
                       @ [ Lget code; I32 2; i32_eq; If (Bnone, untimer @ [ host rt "unwind" ], []) ]
                       @ first
                       @ [ Lget f; struct_get rt.fib fb_late; If (Bnone, failure rt "timeout" Messages.select_timeout @ [ ret ], []);
                           I32 1; Lset again; Br 0 ]);
          unreachable ])
