(* A WebAssembly module, built in memory and written in the binary format: the types of the GC proposal (structs, arrays,
   references), functions, globals, a memory, passive data and custom sections. Functions and globals are named, and
   their indices given when the module is written, imports first, so that what is used can be added in any order. Types
   are numbered as they are added, all in one recursive group. *)

type heap = Func | Extern | Any | Eq | I31 | Struct | Array | Nofunc | None_ | T of int
type vt = I32 | I64 | F64 | Ref of bool * heap  (* nullable, heap type *)
type storage = S of vt | I8
type field = storage * bool  (* mutable *)
type comp = Fn of vt list * vt list | St of field list | Ar of field

(* A block's type: none, one value, or a function type of several. *)
type bt = Bnone | Bval of vt | Btype of int

type ins =
  | Op of int  (* an instruction of one byte, without immediates *)
  | I32 of int
  | I64 of int64
  | F64 of float
  | Lget of int
  | Lset of int
  | Ltee of int
  | Gget of string
  | Gset of string
  | Call of string
  | Ret_call of string
  | Rfunc of string
  | Call_ref of int
  | Block of bt * ins list
  | Loop of bt * ins list
  | If of bt * ins list * ins list
  | Br of int
  | Br_if of int
  | Br_table of int list * int
  | Br_on_null of int
  | Br_on_cast of int * bool * heap * bool * heap  (* depth, from nullable, from, to nullable, to *)
  | Rnull of heap
  | Gc of int * int list  (* 0xFB, its sub-opcode and immediates *)
  | Gcd of int * int * string  (* 0xFB with a type and a data segment: array.new_data, array.init_data *)
  | Test of bool * heap  (* ref.test, nullable *)
  | Cast of bool * heap
  | Fc of int * int list  (* 0xFC, its sub-opcode and immediates *)
  | Mem of int * int * int  (* a load or a store: opcode, alignment, offset *)
  | Data_drop of string
  | Mem_init of string

type func = { fname : string; ftype : int; params : vt list; mutable locals : vt list; mutable body : ins list }

type t = {
  types : comp Vec.t;
  typekeys : (comp, int) Hashtbl.t;
  imports : (string * string * string * int) Vec.t;  (* name, module, field, type *)
  funcs : func Vec.t;
  fnames : (string, unit) Hashtbl.t;
  globals : (string * vt * bool * ins list) Vec.t;  (* name, type, mutable, init *)
  gnames : (string, unit) Hashtbl.t;
  datas : (string * string) Vec.t;  (* name, bytes *)
  dnames : (string, int) Hashtbl.t;
  exports : (string * string) Vec.t;  (* export name, function *)
  customs : (string * string) Vec.t;
  supers : (int, bool * int list) Hashtbl.t;  (* a type declared with its supertypes: final, the supertypes *)
  mutable memory : int;  (* pages, 0 for none *)
}

let create () =
  { types = Vec.create (); typekeys = Hashtbl.create 64; imports = Vec.create (); funcs = Vec.create ();
    fnames = Hashtbl.create 256; globals = Vec.create (); gnames = Hashtbl.create 256; datas = Vec.create ();
    dnames = Hashtbl.create 64; exports = Vec.create (); customs = Vec.create (); supers = Hashtbl.create 8; memory = 0 }

(* A type, added once: the same struct twice is one type. *)
let ty m c =
  match Hashtbl.find_opt m.typekeys c with
  | Some i -> i
  | None ->
    let i = Vec.length m.types in
    Vec.add_last m.types c;
    Hashtbl.replace m.typekeys c i;
    i

(* A struct or array type that no other may equal, though written the same: added always. *)
let fresh_ty m c =
  let i = Vec.length m.types in
  Vec.add_last m.types c;
  i

(* A struct type that others extend (not [final]), or that extends [parents]. *)
let sub_ty m ~final parents c =
  let i = fresh_ty m c in
  Hashtbl.replace m.supers i (final, parents);
  i

let fn_ty m params results = ty m (Fn (params, results))

let find_func m name =
  let r = ref None in
  Vec.iter (fun f -> if f.fname = name then r := Some f) m.funcs;
  match !r with Some f -> f | None -> raise Not_found
let has_func m name = Hashtbl.mem m.fnames name

let import m name modname field params results =
  if not (Hashtbl.mem m.fnames name) then begin
    Hashtbl.replace m.fnames name ();
    Vec.add_last m.imports (name, modname, field, fn_ty m params results)
  end

(* A function, declared before its body so that a body can call it, itself included. *)
let func m name params results =
  Hashtbl.replace m.fnames name ();
  let f = { fname = name; ftype = fn_ty m params results; params; locals = []; body = [] } in
  Vec.add_last m.funcs f;
  f

let has_global m name = Hashtbl.mem m.gnames name

let global m name t mut init =
  if not (Hashtbl.mem m.gnames name) then begin
    Hashtbl.replace m.gnames name ();
    Vec.add_last m.globals (name, t, mut, init)
  end

(* A passive data segment of these bytes, once: its name. *)
let data m bytes =
  match Hashtbl.find_opt m.dnames bytes with
  | Some i -> fst (Vec.get m.datas i)
  | None ->
    let name = "d" ^ string_of_int (Vec.length m.datas) in
    Hashtbl.replace m.dnames bytes (Vec.length m.datas);
    Vec.add_last m.datas (name, bytes);
    name

let export m name f = Vec.add_last m.exports (name, f)
let custom m name payload = Vec.add_last m.customs (name, payload)

(* The encoding. *)

let u b n =
  let n = ref n in
  let continue = ref true in
  while !continue do
    let byte = !n land 0x7f in
    n := !n lsr 7;
    if !n = 0 then begin Buffer.add_char b (Char.chr byte); continue := false end
    else Buffer.add_char b (Char.chr (byte lor 0x80))
  done

let s64 b (n : int64) =
  let n = ref n and continue = ref true in
  while !continue do
    let byte = Int64.to_int (Int64.logand !n 0x7fL) in
    n := Int64.shift_right !n 7;
    if (!n = 0L && byte land 0x40 = 0) || (!n = -1L && byte land 0x40 <> 0) then begin
      Buffer.add_char b (Char.chr byte);
      continue := false
    end
    else Buffer.add_char b (Char.chr (byte lor 0x80))
  done

let s b n = s64 b (Int64.of_int n)
let name b s = u b (String.length s); Buffer.add_string b s

(* The new index of each type that the module uses, while it is written; the others are left out. *)
let renumber = ref [||]
let tyx i = if Array.length !renumber = 0 then i else (!renumber).(i)

let heap b = function
  | Func -> Buffer.add_char b '\x70'
  | Extern -> Buffer.add_char b '\x6f'
  | Any -> Buffer.add_char b '\x6e'
  | Eq -> Buffer.add_char b '\x6d'
  | I31 -> Buffer.add_char b '\x6c'
  | Struct -> Buffer.add_char b '\x6b'
  | Array -> Buffer.add_char b '\x6a'
  | Nofunc -> Buffer.add_char b '\x73'
  | None_ -> Buffer.add_char b '\x71'
  | T i -> s b (tyx i)

let vt b (t : vt) =
  match t with
  | I32 -> Buffer.add_char b '\x7f'
  | I64 -> Buffer.add_char b '\x7e'
  | F64 -> Buffer.add_char b '\x7c'
  | Ref (null, h) -> Buffer.add_char b (if null then '\x63' else '\x64'); heap b h

let vec b f xs = u b (List.length xs); List.iter (f b) xs

let field b ((st, mut) : field) =
  (match st with S (t : vt) -> vt b t | I8 -> Buffer.add_char b '\x78');
  Buffer.add_char b (if mut then '\x01' else '\x00')

let comp b = function
  | Fn (ps, rs) -> Buffer.add_char b '\x60'; vec b vt ps; vec b vt rs
  | St fs -> Buffer.add_char b '\x5f'; vec b field fs
  | Ar f -> Buffer.add_char b '\x5e'; field b f

let section out id f =
  let b = Buffer.create 256 in
  f b;
  if Buffer.length b > 0 || id = 0 then begin
    Buffer.add_char out (Char.chr id);
    u out (Buffer.length b);
    Buffer.add_buffer out b
  end

exception Unknown of string

(* The immediates of a 0xFB instruction that are types: the first of those that make or touch a struct or an array,
   both of array.copy. *)
let type_imm op j = ((op <= 14 || op = 16 || op = 18) && j = 0) || (op = 17 && j <= 1)

(* The types that the imports, functions and globals use, and those these use: the others need not be written. *)
let used_types m =
  let used = Array.make (Vec.length m.types) false in
  let rec mark i =
    if not used.(i) then begin
      used.(i) <- true;
      (match Vec.get m.types i with
       | Fn (ps, rs) -> List.iter vt_mark ps; List.iter vt_mark rs
       | St fs -> List.iter field_mark fs
       | Ar f -> field_mark f);
      match Hashtbl.find_opt m.supers i with Some (_, ps) -> List.iter mark ps | None -> ()
    end
  and heap_mark = function T i -> mark i | _ -> ()
  and vt_mark = function Ref (_, h) -> heap_mark h | _ -> ()
  and field_mark (st, _) = match st with S t -> vt_mark t | I8 -> () in
  let bt_mark = function Btype t -> mark t | Bval v -> vt_mark v | Bnone -> () in
  let rec ins = function
    | Block (bt, is) | Loop (bt, is) -> bt_mark bt; List.iter ins is
    | If (bt, y, n) -> bt_mark bt; List.iter ins y; List.iter ins n
    | Call_ref t -> mark t
    | Br_on_cast (_, _, h1, _, h2) -> heap_mark h1; heap_mark h2
    | Rnull h | Test (_, h) | Cast (_, h) -> heap_mark h
    | Gc (op, imms) -> List.iteri (fun j t -> if type_imm op j then mark t) imms
    | Gcd (_, t, _) -> mark t
    | _ -> ()
  in
  Vec.iter (fun (_, _, _, t) -> mark t) m.imports;
  Vec.iter (fun f -> mark f.ftype; List.iter vt_mark f.locals; List.iter ins f.body) m.funcs;
  Vec.iter (fun (_, t, _, init) -> vt_mark t; List.iter ins init) m.globals;
  used

let iteri f v = for i = 0 to Vec.length v - 1 do f i (Vec.get v i) done

let write m =
  let used = used_types m in
  let next = ref 0 in
  renumber := Array.map (fun u -> if u then (incr next; !next - 1) else -1) used;
  Fun.protect ~finally:(fun () -> renumber := [||]) (fun () ->
  let fidx = Hashtbl.create 256 in
  iteri (fun i (n, _, _, _) -> Hashtbl.replace fidx n i) m.imports;
  let ni = Vec.length m.imports in
  iteri (fun i f -> Hashtbl.replace fidx f.fname (ni + i)) m.funcs;
  let gidx = Hashtbl.create 256 in
  iteri (fun i (n, _, _, _) -> Hashtbl.replace gidx n i) m.globals;
  let didx = Hashtbl.create 64 in
  iteri (fun i (n, _) -> Hashtbl.replace didx n i) m.datas;
  let find t n = match Hashtbl.find_opt t n with Some i -> i | None -> raise (Unknown n) in
  let refs = Hashtbl.create 64 in
  let bt b = function Bnone -> Buffer.add_char b '\x40' | Bval t -> vt b t | Btype i -> s b (tyx i) in
  let rec ins b = function
    | Op o -> Buffer.add_char b (Char.chr o)
    | I32 n -> Buffer.add_char b '\x41'; s64 b (Int64.of_int32 (Int32.of_int n))
    | I64 n -> Buffer.add_char b '\x42'; s64 b n
    | F64 x -> Buffer.add_char b '\x44'; Buffer.add_int64_le b (Int64.bits_of_float x)
    | Lget i -> Buffer.add_char b '\x20'; u b i
    | Lset i -> Buffer.add_char b '\x21'; u b i
    | Ltee i -> Buffer.add_char b '\x22'; u b i
    | Gget n -> Buffer.add_char b '\x23'; u b (find gidx n)
    | Gset n -> Buffer.add_char b '\x24'; u b (find gidx n)
    | Call n -> Buffer.add_char b '\x10'; u b (find fidx n)
    | Ret_call n -> Buffer.add_char b '\x12'; u b (find fidx n)
    | Rfunc n -> Hashtbl.replace refs (find fidx n) (); Buffer.add_char b '\xd2'; u b (find fidx n)
    | Call_ref t -> Buffer.add_char b '\x14'; u b (tyx t)
    | Block (t, is) -> Buffer.add_char b '\x02'; bt b t; List.iter (ins b) is; Buffer.add_char b '\x0b'
    | Loop (t, is) -> Buffer.add_char b '\x03'; bt b t; List.iter (ins b) is; Buffer.add_char b '\x0b'
    | If (t, y, n) ->
      Buffer.add_char b '\x04';
      bt b t;
      List.iter (ins b) y;
      if n <> [] then begin Buffer.add_char b '\x05'; List.iter (ins b) n end;
      Buffer.add_char b '\x0b'
    | Br l -> Buffer.add_char b '\x0c'; u b l
    | Br_if l -> Buffer.add_char b '\x0d'; u b l
    | Br_table (ls, d) -> Buffer.add_char b '\x0e'; vec b u ls; u b d
    | Br_on_null l -> Buffer.add_char b '\xd5'; u b l
    | Br_on_cast (l, n1, h1, n2, h2) ->
      Buffer.add_string b "\xfb\x18";
      Buffer.add_char b (Char.chr ((if n1 then 1 else 0) lor if n2 then 2 else 0));
      u b l;
      heap b h1;
      heap b h2
    | Rnull h -> Buffer.add_char b '\xd0'; heap b h
    | Gc (op, imms) -> Buffer.add_char b '\xfb'; u b op; List.iteri (fun j x -> u b (if type_imm op j then tyx x else x)) imms
    | Gcd (op, t, d) -> Buffer.add_char b '\xfb'; u b op; u b (tyx t); u b (find didx d)
    | Test (null, h) -> Buffer.add_char b '\xfb'; u b (if null then 21 else 20); heap b h
    | Cast (null, h) -> Buffer.add_char b '\xfb'; u b (if null then 23 else 22); heap b h
    | Fc (op, imms) -> Buffer.add_char b '\xfc'; u b op; List.iter (u b) imms
    | Mem (op, align, off) -> Buffer.add_char b (Char.chr op); u b align; u b off
    | Data_drop d -> Buffer.add_char b '\xfc'; u b 9; u b (find didx d)
    | Mem_init d -> Buffer.add_char b '\xfc'; u b 8; u b (find didx d); Buffer.add_char b '\x00'
  in
  (* The code first, as it finds the functions that ref.func names, which must be declared. *)
  let code = Buffer.create 65536 in
  u code (Vec.length m.funcs);
  Vec.iter
    (fun f ->
       let b = Buffer.create 256 in
       (* Runs of locals of one type. *)
       let rec runs acc = function
         | [] -> List.rev acc
         | t :: rest ->
           (match acc with
            | (n, t') :: acc' when t' = t -> runs ((n + 1, t) :: acc') rest
            | _ -> runs ((1, t) :: acc) rest)
       in
       vec b (fun b (n, t) -> u b n; vt b t) (runs [] f.locals);
       List.iter (ins b) f.body;
       Buffer.add_char b '\x0b';
       u code (Buffer.length b);
       Buffer.add_buffer code b)
    m.funcs;
  let globals = Buffer.create 1024 in
  u globals (Vec.length m.globals);
  Vec.iter
    (fun (_, t, mut, init) ->
       vt globals t;
       Buffer.add_char globals (if mut then '\x01' else '\x00');
       List.iter (ins globals) init;
       Buffer.add_char globals '\x0b')
    m.globals;
  let out = Buffer.create 65536 in
  Buffer.add_string out "\x00asm\x01\x00\x00\x00";
  section out 1 (fun b ->
      if !next > 0 then begin
        u b 1;
        Buffer.add_char b '\x4e';
        u b !next;
        iteri
          (fun i c ->
             if used.(i) then begin
               (match Hashtbl.find_opt m.supers i with
                | Some (final, parents) -> Buffer.add_char b (if final then '\x4f' else '\x50'); vec b u (List.map tyx parents)
                | None -> ());
               comp b c
             end)
          m.types
      end);
  section out 2 (fun b ->
      if Vec.length m.imports > 0 then begin
        u b (Vec.length m.imports);
        Vec.iter (fun (_, md, fd, t) -> name b md; name b fd; Buffer.add_char b '\x00'; u b (tyx t)) m.imports
      end);
  section out 3 (fun b -> if Vec.length m.funcs > 0 then begin u b (Vec.length m.funcs); Vec.iter (fun f -> u b (tyx f.ftype)) m.funcs end);
  section out 5 (fun b -> if m.memory > 0 then begin u b 1; Buffer.add_char b '\x00'; u b m.memory end);
  section out 6 (fun b -> if Vec.length m.globals > 0 then Buffer.add_buffer b globals);
  section out 7 (fun b ->
      let n = Vec.length m.exports + if m.memory > 0 then 1 else 0 in
      if n > 0 then begin
        u b n;
        Vec.iter (fun (e, f) -> name b e; Buffer.add_char b '\x00'; u b (find fidx f)) m.exports;
        if m.memory > 0 then begin name b "memory"; Buffer.add_char b '\x02'; u b 0 end
      end);
  section out 9 (fun b ->
      if Hashtbl.length refs > 0 then begin
        u b 1;
        (* Declarative: the functions that ref.func names. *)
        u b 3;
        Buffer.add_char b '\x00';
        let fs = List.sort compare (Hashtbl.fold (fun f () acc -> f :: acc) refs []) in
        vec b u fs
      end);
  section out 12 (fun b -> if Vec.length m.datas > 0 then u b (Vec.length m.datas));
  section out 10 (fun b -> if Vec.length m.funcs > 0 then Buffer.add_buffer b code);
  section out 11 (fun b ->
      if Vec.length m.datas > 0 then begin
        u b (Vec.length m.datas);
        Vec.iter (fun (_, bytes) -> u b 1; name b bytes) m.datas
      end);
  Vec.iter (fun (n, payload) -> section out 0 (fun b -> name b n; Buffer.add_string b payload)) m.customs;
  (* With CESIA_WASM_NAMES, the functions' names, for the engines' messages and stacks. *)
  if Sys.getenv_opt "CESIA_WASM_NAMES" <> None then
    section out 0 (fun b ->
        name b "name";
        let sub = Buffer.create 1024 in
        u sub (Vec.length m.imports + Vec.length m.funcs);
        iteri (fun i (n, _, _, _) -> u sub i; name sub n) m.imports;
        iteri (fun i f -> u sub (ni + i); name sub f.fname) m.funcs;
        Buffer.add_char b '\x01';
        u b (Buffer.length sub);
        Buffer.add_buffer b sub);
  Buffer.contents out)
