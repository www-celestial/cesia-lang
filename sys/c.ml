open Kepler
open Types

external call : int -> int -> Bytes.t -> string array -> int -> unit = "kepler_call" [@@noalloc]
external dlopen : string -> int = "kepler_dlopen"
external dlsym : int -> string -> int = "kepler_dlsym"
external dlerror : unit -> string = "kepler_dlerror"
external cstring : int -> string = "kepler_cstring"

type memory = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

external block_address : memory -> int = "kepler_block_address"
external get16 : memory -> int -> int = "%caml_bigstring_get16"
external get32 : memory -> int -> int32 = "%caml_bigstring_get32"
external get64 : memory -> int -> int64 = "%caml_bigstring_get64"
external set16 : memory -> int -> int -> unit = "%caml_bigstring_set16"
external set32 : memory -> int -> int32 -> unit = "%caml_bigstring_set32"
external set64 : memory -> int -> int64 -> unit = "%caml_bigstring_set64"

type ty = I8 | U8 | I16 | U16 | I32 | U32 | I64 | U64 | F32 | F64 | Bool | Ptr | Text | Void

let types =
  [ "i8", I8; "u8", U8; "i16", I16; "u16", U16; "i32", I32; "u32", U32; "i64", I64; "u64", U64; "f32", F32; "f64", F64;
    "bool", Bool; "ptr", Ptr; "text", Text; "void", Void ]

let name_of ty = fst (List.find (fun (_, t) -> t = ty) types)

(* Memory outside the OCaml heap, which doesn't move and which C can keep. *)
type block = { data : memory; address : int; size : int }

(* The arguments and the result of a call: [slots] holds six words, then the result. The address of a text is taken in
   C, at the last moment, because the GC can move a text until then. *)
type t = {
  slots : Bytes.t;
  texts : string array;
  blocks : (int, block) Hashtbl.t;  (** by id: an id is never used twice, so a stale handle finds nothing *)
  mutable next_block : int;
  mutable live_bytes : int;
  mutable opened : bool;  (** a granted library is open: only then can a pointer exist *)
}

let max_args = 6
let result_offset = 48

let create () =
  { slots = Bytes.make 56 '\000'; texts = Array.make max_args ""; blocks = Hashtbl.create 16; next_block = 1;
    live_bytes = 0; opened = false }

(* Work that grows with its input pays in steps, at the rate of a text. *)
let pay_bytes ctx n = Runtime.charge ctx ((n / 128) + 1)

let c_name ctx name v =
  let s = Native.text_arg ctx name v in
  pay_bytes ctx (String.length s);
  if String.contains s '\000' then Runtime.fail ctx Type Messages.c_zero_byte;
  s

let ty_of ctx v =
  let name = Native.text_arg ctx "fn" v in
  match List.assoc_opt name types with
  | Some ty -> ty
  | None -> Runtime.fail ctx Type (Messages.c_type name)

let is_float = function F32 | F64 -> true | _ -> false

(* The position of a signature in the table of gen/gen_calls.ml. *)
let shape_id args ret =
  let mask = ref 0 in
  Array.iteri (fun k ty -> if is_float ty then mask := !mask lor (1 lsl k)) args;
  (((1 lsl Array.length args) - 1 + !mask) * 2) + if is_float ret then 1 else 0

let int_range = function
  | I8 -> -0x80, 0x7F
  | U8 -> 0, 0xFF
  | I16 -> -0x8000, 0x7FFF
  | U16 -> 0, 0xFFFF
  | I32 -> -0x80000000, 0x7FFFFFFF
  | U32 -> 0, 0xFFFFFFFF
  | I64 -> min_int, max_int
  | _ -> 0, max_int

let write st k x = Bytes.set_int64_ne st.slots (k * 8) x
let fail ctx message = Runtime.fail ctx Type message

(* An integer as C takes it, or a panic. *)
let integer ctx ty (v : Types.t) =
  match v with
  | Int i ->
    let low, high = int_range ty in
    if i < low || i > high then fail ctx (Messages.c_fit (string_of_int i) (name_of ty));
    Int64.of_int i
  | _ -> fail ctx (Messages.c_need_integer (name_of ty) (Value.describe v))

let number ctx ty (v : Types.t) =
  match v with
  | Float x -> x
  | Int i -> float_of_int i
  | _ -> fail ctx (Messages.c_need_number (name_of ty) (Value.describe v))

(* A float travels in the low half of a double: the register is the same. *)
let float_bits ctx ty v =
  match ty with
  | F32 -> Int64.of_int32 (Int32.bits_of_float (number ctx ty v))
  | _ -> Int64.bits_of_float (number ctx ty v)

let boolean ctx (v : Types.t) =
  match v with
  | True -> 1L
  | False -> 0L
  | _ -> fail ctx (Messages.c_need_bool (Value.describe v))

let live_block st ctx id =
  match Hashtbl.find_opt st.blocks id with
  | Some b -> b
  | None -> fail ctx Messages.c_freed

let address st ctx (v : Types.t) =
  match v with
  | Missing -> 0L
  | Handle { kind = "pointer"; id; _ } -> Int64.of_int id
  | Handle { kind = "block"; id; _ } -> Int64.of_int (live_block st ctx id).address
  | _ -> fail ctx (Messages.c_need_ptr (Value.describe v))

(* Writes an argument. Gives the bit of the mask for a text. *)
let arg_slot st ctx k ty (v : Types.t) =
  match ty with
  | I8 | U8 | I16 | U16 | I32 | U32 | I64 | U64 -> write st k (integer ctx ty v); 0
  | F32 | F64 -> write st k (float_bits ctx ty v); 0
  | Bool -> write st k (boolean ctx v); 0
  | Ptr -> write st k (address st ctx v); 0
  | Void -> 0
  | Text ->
    (match v with
     | Types.Text s ->
       if String.contains s '\000' then fail ctx Messages.c_zero_byte;
       st.texts.(k) <- s;
       1 lsl k
     | Missing -> write st k 0L; 0
     | _ -> fail ctx (Messages.c_need_text (Value.describe v)))

let sign_extend bits i = (i lsl (Sys.int_size - bits)) asr (Sys.int_size - bits)
let pointer id : Types.t = Handle { kind = "pointer"; id; task = None }

(* The upper bits of a narrow result are undefined. *)
let return_value ctx ty r : Types.t =
  let i = Int64.to_int r in
  let whole () = if Int64.of_int i <> r then fail ctx (Messages.c_return_fit (name_of ty)) in
  match ty with
  | I8 -> Int (sign_extend 8 i)
  | U8 -> Int (i land 0xFF)
  | I16 -> Int (sign_extend 16 i)
  | U16 -> Int (i land 0xFFFF)
  | I32 -> Int (sign_extend 32 i)
  | U32 -> Int (i land 0xFFFFFFFF)
  | I64 -> whole (); Int i
  | U64 -> whole (); if i < 0 then fail ctx (Messages.c_return_fit "u64"); Int i
  | F32 -> Float (Int32.float_of_bits (Int64.to_int32 r))
  | F64 -> Float (Int64.float_of_bits r)
  | Bool -> Value.of_bool (i land 0xFF <> 0)
  | Ptr -> if i = 0 then Missing else pointer i
  | Text -> if i = 0 then Missing else Types.Text (cstring i)
  | Void -> Missing

let c_function st name address args ret =
  let id = shape_id args ret and n = Array.length args in
  Native.nat name n n (fun ctx a ->
      let mask = ref 0 in
      for k = 0 to n - 1 do
        mask := !mask lor arg_slot st ctx k args.(k) a.(k)
      done;
      call address id st.slots st.texts !mask;
      return_value ctx ret (Bytes.get_int64_ne st.slots result_offset))

(* Every usual name of every OS: a name from another OS just fails to load. None may be relative with a slash, since
   the loader would read that from the current folder, where anyone can plant a file. *)
let candidates name version =
  if String.contains name '/' || String.contains name '\\' then [ name ]
  else begin
    let versioned f = Option.to_list (Option.map f version) in
    versioned (Printf.sprintf "lib%s.so.%s" name)
    @ [ Printf.sprintf "lib%s.so" name ]
    @ versioned (Printf.sprintf "lib%s.%s.dylib" name)
    @ [ Printf.sprintf "lib%s.dylib" name;
        Printf.sprintf "/Library/Frameworks/%s.framework/%s" name name;
        name ^ ".dll";
        Printf.sprintf "lib%s.dll" name ]
  end

let version_arg ctx (a : Types.t array) =
  match if Array.length a > 1 then a.(1) else Undef with
  | Undef | Missing -> None
  | Int i -> Some (string_of_int i)
  | Types.Text s -> Some s
  | v -> Runtime.fail ctx Type (Messages.c_version (Value.describe v))

let library address : Types.t = Handle { kind = "library"; id = address; task = None }

let open_library st ctx (a : Types.t array) =
  let name = c_name ctx "open" a.(0) in
  Runtime.check_perm ctx Ffi (Some name);
  (* The first reason is the one for the most exact name. *)
  let load (found, reason) path =
    if found <> 0 then found, reason
    else begin
      let handle = dlopen path in
      handle, if handle = 0 && reason = "" then dlerror () else reason
    end
  in
  match List.fold_left load (0, "") (candidates name (version_arg ctx a)) with
  | 0, reason -> Fs.failure ctx.w "c" (Messages.c_no_library name reason).text
  | address, _ ->
    st.opened <- true;
    Value.ok ctx.w (library address)

let types_of ctx (v : Types.t) =
  match v with
  | Array x ->
    let n = x.rows * x.cols in
    if n > max_args then Runtime.fail ctx Type (Messages.c_too_many n);
    Array.init n (fun k -> ty_of ctx (Value.elt x k))
  | _ -> Runtime.fail ctx Type (Messages.need_array "fn" (Value.describe v))

let bind st ctx (a : Types.t array) =
  let name = c_name ctx "fn" a.(0) in
  let args = types_of ctx a.(1) and ret = ty_of ctx a.(2) in
  if Array.mem Void args then Runtime.fail ctx Type Messages.c_void_arg;
  match a.(3) with
  | Handle { kind = "library"; id = lib; _ } ->
    (match dlsym lib name with
     | 0 -> Fs.failure ctx.w "c" (Messages.c_no_function name).text
     | address -> Value.ok ctx.w (c_function st name address args ret))
  | v -> Runtime.fail ctx Type (Messages.c_need_library (Value.describe v))

let alloc st ctx (a : Types.t array) : Types.t =
  match a.(0) with
  | Int size when size >= 1 ->
    let most = ctx.w.limits.memory_words in
    let most_bytes = if most > max_int / 8 then max_int else most * 8 in
    if size > most_bytes - st.live_bytes then Runtime.limit "memory" ctx.site;
    (match Bigarray.Array1.create Bigarray.char Bigarray.c_layout size with
     | exception (Out_of_memory | Invalid_argument _) -> Runtime.limit "memory" ctx.site
     | data ->
       Bigarray.Array1.fill data '\000';
       let id = st.next_block in
       st.next_block <- id + 1;
       st.live_bytes <- st.live_bytes + size;
       Hashtbl.replace st.blocks id { data; address = block_address data; size };
       pay_bytes ctx size;
       Handle { kind = "block"; id; task = None })
  | v -> fail ctx (Messages.c_size (Value.describe v))

let block_arg st ctx name (v : Types.t) =
  match v with
  | Handle { kind = "block"; id; _ } -> id, live_block st ctx id
  | _ -> fail ctx (Messages.c_need_block name (Value.describe v))

let free st ctx (a : Types.t array) : Types.t =
  let id, b = block_arg st ctx "free" a.(0) in
  Hashtbl.remove st.blocks id;
  st.live_bytes <- st.live_bytes - b.size;
  Missing

let width = function
  | I8 | U8 | Bool -> 1
  | I16 | U16 -> 2
  | I32 | U32 | F32 -> 4
  | _ -> 8

let offset_arg ctx ty (b : block) (v : Types.t) =
  match v with
  | Int o when o >= 0 && o <= b.size - width ty -> o
  | Int o -> fail ctx (Messages.c_offset o b.size (name_of ty))
  | _ -> fail ctx (Messages.c_need_offset (Value.describe v))

(* The same conversions as a call: a word read here is what a C function would have returned. *)
let get st ctx (a : Types.t array) =
  let ty = ty_of ctx a.(0) in
  let _, b = block_arg st ctx "get" a.(2) in
  if ty = Text || ty = Void then fail ctx (Messages.c_block_type "read from" (name_of ty));
  if ty = Ptr && not st.opened then fail ctx Messages.c_no_open_library;
  let o = offset_arg ctx ty b a.(1) in
  let word =
    match width ty with
    | 1 -> Int64.of_int (Char.code b.data.{o})
    | 2 -> Int64.of_int (get16 b.data o)
    | 4 -> Int64.of_int32 (get32 b.data o)
    | _ -> get64 b.data o
  in
  return_value ctx ty word

let set st ctx (a : Types.t array) : Types.t =
  let ty = ty_of ctx a.(0) in
  let _, b = block_arg st ctx "set" a.(3) in
  if ty = Text || ty = Void then fail ctx (Messages.c_block_type "written to" (name_of ty));
  if ty = Ptr && not st.opened then fail ctx Messages.c_no_open_library;
  let o = offset_arg ctx ty b a.(1) in
  let word =
    match ty with
    | F32 | F64 -> float_bits ctx ty a.(2)
    | Bool -> boolean ctx a.(2)
    | Ptr -> address st ctx a.(2)
    | _ -> integer ctx ty a.(2)
  in
  (match width ty with
   | 1 -> b.data.{o} <- Char.chr (Int64.to_int word land 0xFF)
   | 2 -> set16 b.data o (Int64.to_int word)
   | 4 -> set32 b.data o (Int64.to_int32 word)
   | _ -> set64 b.data o word);
  Missing

let text st ctx (a : Types.t array) : Types.t =
  if not st.opened then fail ctx Messages.c_no_open_library;
  match a.(0) with
  | Handle { kind = "pointer"; id; _ } -> Types.Text (cstring id)
  | v -> fail ctx (Messages.c_need_pointer (Value.describe v))

let natives st =
  [ "open", Native.nat ~params:[| "name"; "version" |] "open" 1 2 (open_library st);
    "fn", Native.nat "fn" 4 4 (bind st);
    "alloc", Native.nat "alloc" 1 1 (alloc st);
    "free", Native.nat "free" 1 1 (free st);
    "get", Native.nat "get" 3 3 (get st);
    "set", Native.nat "set" 4 4 (set st);
    "text", Native.nat "text" 1 1 (text st) ]
