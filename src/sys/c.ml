open Cesia
open Types

external call : int -> int -> Bytes.t -> string array -> int -> unit = "cesia_call" [@@noalloc]
external dlopen : string -> int = "cesia_dlopen"
external dlsym : int -> string -> int = "cesia_dlsym"
external dlerror : unit -> string = "cesia_dlerror"
external cstring : int -> string = "cesia_cstring"

type memory = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

external block_address : memory -> int = "cesia_block_address"
external ffi_load : unit -> int = "cesia_ffi_load"
external ffi_type : int -> int -> int = "cesia_ffi_type"
external ffi_struct : int array -> int = "cesia_ffi_struct"
external ffi_cif : int -> int -> int array -> int -> int = "cesia_ffi_cif"
external ffi_invoke : int -> int -> Bytes.t -> int -> int -> unit = "cesia_ffi_invoke"
external ffi_closure : int -> (int -> int -> unit) -> int = "cesia_ffi_closure"
external strdup : string -> int = "cesia_strdup"
external free_text : int -> unit = "cesia_free"
external peek : int -> int -> int64 = "cesia_peek"
external poke : int -> int64 -> unit = "cesia_poke"
external get16 : memory -> int -> int = "%caml_bigstring_get16"
external get32 : memory -> int -> int32 = "%caml_bigstring_get32"
external get64 : memory -> int -> int64 = "%caml_bigstring_get64"
external set16 : memory -> int -> int -> unit = "%caml_bigstring_set16"
external set32 : memory -> int -> int32 -> unit = "%caml_bigstring_set32"
external set64 : memory -> int -> int64 -> unit = "%caml_bigstring_set64"

type ty = I8 | U8 | I16 | U16 | I32 | U32 | I64 | U64 | F32 | F64 | Bool | Ptr | Text | Void | Callback | Aggregate of layout
and layout = { fields : ty array; offsets : int array; size : int; alignment : int; description : int }

let types =
  [ "i8", I8; "u8", U8; "i16", I16; "u16", U16; "i32", I32; "u32", U32; "i64", I64; "u64", U64; "f32", F32; "f64", F64;
    "bool", Bool; "ptr", Ptr; "text", Text; "void", Void; "callback", Callback ]

let name_of = function
  | Aggregate _ -> "a structure"
  | ty -> fst (List.find (fun (_, t) -> t = ty) types)

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
  layouts : (int, layout) Hashtbl.t;  (** structures, by id *)
  mutable ffi : int;  (** libffi's table, once loaded *)
  mutable pending : exn option;  (** a panic in a callback: it can't cross the C frames, so it waits for their end *)
  mutable spare : ctx option;  (** the context of callbacks, free between two *)
  mutable calling : int;  (** how many calls through libffi are running, so a callback may be under way *)
  mutable freed : block list;  (** blocks freed during such a call: C may still be reading them *)
}

let max_args = 6
let max_ffi_args = 60
let result_offset = 48

let create () =
  { slots = Bytes.make 56 '\000'; texts = Array.make max_args ""; blocks = Hashtbl.create 16; next_block = 1;
    live_bytes = 0; opened = false; layouts = Hashtbl.create 8; ffi = 0; pending = None; spare = None;
    calling = 0; freed = [] }

let c_name ctx name v =
  let s = Native.text_arg ctx name v in
  Runtime.pay_bytes ctx (String.length s);
  if String.contains s '\000' then Runtime.fail ctx Type Messages.c_zero_byte;
  s

let ty_of st ctx (v : Types.t) =
  match v with
  | Handle { kind = "ctype"; id; _ } -> Aggregate (Hashtbl.find st.layouts id)
  | _ ->
  let name = Native.text_arg ctx "Fn" v in
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
  | Handle { kind = "callback"; id; _ } -> Int64.of_int id
  | _ -> fail ctx (Messages.c_need_ptr (Value.describe v))

let scalar st ctx ty v =
  match ty with
  | F32 | F64 -> float_bits ctx ty v
  | Bool -> boolean ctx v
  | Ptr -> address st ctx v
  | _ -> integer ctx ty v

(* Writes an argument. Gives the bit of the mask for a text. *)
let arg_slot st ctx k ty (v : Types.t) =
  match ty with
  | Void | Callback | Aggregate _ -> 0
  | Text ->
    (match v with
     | Types.Text s ->
       if String.contains s '\000' then fail ctx Messages.c_zero_byte;
       st.texts.(k) <- s;
       1 lsl k
     | Missing -> write st k 0L; 0
     | _ -> fail ctx (Messages.c_need_text (Value.describe v)))
  | _ -> write st k (scalar st ctx ty v); 0

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
  | Void | Callback | Aggregate _ -> Missing

let c_function st name address args ret =
  let id = shape_id args ret and n = Array.length args in
  Native.nat name n n (fun ctx a ->
      let mask = ref 0 in
      for k = 0 to n - 1 do
        mask := !mask lor arg_slot st ctx k args.(k) a.(k)
      done;
      call address id st.slots st.texts !mask;
      return_value ctx ret (Bytes.get_int64_ne st.slots result_offset))

(* Where Homebrew puts libraries, which macOS doesn't search, and the folder of its OpenSSL, which it links nowhere else. *)
let brew = [ "/opt/homebrew/lib"; "/opt/homebrew/opt/openssl@3/lib"; "/usr/local/lib"; "/usr/local/opt/openssl@3/lib" ]

(* On macOS, libssl.dylib and libcrypto.dylib with no version are stubs of the system that abort the process that loads them. *)
let stubs = [ "libssl.dylib"; "libcrypto.dylib" ]

(* Every usual name of every OS: a name from another OS just fails to load. None may be relative with a slash, since
   the loader would read that from the current folder, where anyone can plant a file. The names with the version come first,
   also in Homebrew's folders, then those without it, which may be another version: libm.dylib of macOS has none, and a
   system can hold libsodium.so.23 where 26 is asked. *)
(* The lib/ of a release, beside the bin/ that holds the binary, found from the binary itself with its links followed, never
   from the current folder; only with its licenses/Cesia.txt, so that the /usr/local/lib of a binary copied by hand is no
   release's. *)
let beside =
  lazy
    (match Unix.realpath Sys.executable_name with
     | exception Unix.Unix_error _ -> None
     | exe ->
       let bin = Filename.dirname exe in
       let lib = Filename.concat (Filename.dirname bin) "lib" in
       if Filename.basename bin = "bin" && Sys.file_exists (Filename.concat lib "licenses/Cesia.txt") then Some lib else None)

let in_release files =
  match Lazy.force beside with
  | None -> []
  | Some lib -> List.filter_map (fun f -> if Filename.basename f = f then Some (Filename.concat lib f) else None) files

let candidates name version =
  if String.contains name '/' || String.contains name '\\' then [ name ]
  else begin
    let names so dylib = so :: dylib :: List.map (fun dir -> Filename.concat dir dylib) brew in
    let versioned =
      match version with
      | Some v ->
        names (Printf.sprintf "lib%s.so.%s" name v) (Printf.sprintf "lib%s.%s.dylib" name v)
        @ [ Printf.sprintf "lib%s-%s-x64.dll" name v ]
      | None -> []
    in
    let plain = List.filter (fun file -> not (List.mem (Filename.basename file) stubs)) (names (Printf.sprintf "lib%s.so" name) (Printf.sprintf "lib%s.dylib" name)) in
    let usual =
      versioned @ plain
      @ [ Printf.sprintf "/Library/Frameworks/%s.framework/%s" name name; name ^ ".dll"; Printf.sprintf "lib%s.dll" name ]
    in
    in_release usual @ usual
  end

let version_arg ctx (a : Types.t array) =
  match if Array.length a > 1 then a.(1) else Undef with
  | Undef | Missing -> None
  | Int i -> Some (string_of_int i)
  | Types.Text s -> Some s
  | v -> Runtime.fail ctx Type (Messages.c_version (Value.describe v))

let library address : Types.t = Handle { kind = "library"; id = address; task = None }

(* SQLite has one way in, std/sql, which checks the files a database reaches: never through c. *)
let is_sqlite name =
  let base = String.lowercase_ascii (Filename.basename name) in
  String.starts_with ~prefix:"sqlite3" base || String.starts_with ~prefix:"libsqlite3" base

let open_library st ctx (a : Types.t array) =
  let name = c_name ctx "Open" a.(0) in
  if is_sqlite name then Fs.failure ctx.w "c" (Messages.c_sqlite name).text else begin
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
  end

let types_of st ctx (v : Types.t) =
  match v with
  | Array x ->
    let n = x.rows * x.cols in
    if n > max_ffi_args then Runtime.fail ctx Type (Messages.c_too_many n);
    Array.init n (fun k -> ty_of st ctx (Value.elt x k))
  | _ -> Runtime.fail ctx Type (Messages.need_array "Fn" (Value.describe v))

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
       Runtime.pay_bytes ctx size;
       Handle { kind = "block"; id; task = None })
  | v -> fail ctx (Messages.c_size (Value.describe v))

let new_block st ctx size =
  match alloc st ctx [| Int size |] with
  | Handle { id; _ } as handle -> handle, live_block st ctx id
  | _ -> assert false

let block_arg st ctx name (v : Types.t) =
  match v with
  | Handle { kind = "block"; id; _ } -> id, live_block st ctx id
  | _ -> fail ctx (Messages.c_need_block name (Value.describe v))

let free st ctx (a : Types.t array) : Types.t =
  let id, b = block_arg st ctx "Free" a.(0) in
  Hashtbl.remove st.blocks id;
  st.live_bytes <- st.live_bytes - b.size;
  if st.calling > 0 then st.freed <- b :: st.freed;
  Missing

let width = function
  | I8 | U8 | Bool -> 1
  | I16 | U16 -> 2
  | I32 | U32 | F32 -> 4
  | Aggregate l -> l.size
  | _ -> 8

let alignment_of = function
  | Aggregate l -> l.alignment
  | ty -> width ty

(* Through libffi. It stays unloaded until a program needs it, and a program with no library has no use for it. *)
let ready st ctx =
  if not st.opened then fail ctx Messages.c_no_open_library;
  if st.ffi = 0 then st.ffi <- ffi_load ();
  if st.ffi = 0 then fail ctx Messages.c_no_ffi

let description st = function
  | Aggregate l -> l.description
  | ty ->
    ffi_type st.ffi
      (match ty with
       | Void -> 0 | U8 | Bool -> 1 | I8 -> 2 | U16 -> 3 | I16 -> 4 | U32 -> 5 | I32 -> 6 | U64 -> 7 | I64 -> 8 | F32 -> 9
       | F64 -> 10 | Ptr | Text | Callback | Aggregate _ -> 11)

let signature st ctx args ret fixed =
  match ffi_cif st.ffi (description st ret) (Array.map (description st) args) fixed with
  | 0 -> fail ctx Messages.c_bad_signature
  | cif -> cif

(* Writes an argument, which stays valid across a callback: the GC can't move what C reads. *)
let encode st ctx slots structs texts k ty (v : Types.t) =
  let put x = Bytes.set_int64_ne slots (k * 8) x in
  match ty, v with
  | Aggregate l, Handle { kind = "block"; id; _ } ->
    let b = live_block st ctx id in
    if b.size < l.size then fail ctx (Messages.c_small_block b.size l.size);
    put (Int64.of_int b.address);
    structs := !structs lor (1 lsl k)
  | Aggregate _, _ -> fail ctx (Messages.c_need_struct (Value.describe v))
  | Callback, Handle { kind = "callback"; id; _ } -> put (Int64.of_int id)
  | Callback, _ -> fail ctx (Messages.c_need_callback (Value.describe v))
  | Text, Types.Text s ->
    if String.contains s '\000' then fail ctx Messages.c_zero_byte;
    let p = strdup s in
    texts := p :: !texts;
    put (Int64.of_int p)
  | Text, Missing -> put 0L
  | Text, _ -> fail ctx (Messages.c_need_text (Value.describe v))
  | _ -> put (scalar st ctx ty v)

let rethrow st =
  match st.pending with
  | Some e ->
    st.pending <- None;
    raise e
  | None -> ()

let ffi_function st ctx name address args ret fixed =
  let cif = signature st ctx args ret fixed and n = Array.length args in
  Native.nat name n n (fun ctx a ->
      let slots = Bytes.make (8 * (n + 1)) '\000' and structs = ref 0 and texts = ref [] in
      st.calling <- st.calling + 1;
      Fun.protect
        ~finally:(fun () ->
          List.iter free_text !texts;
          st.calling <- st.calling - 1;
          if st.calling = 0 then st.freed <- [])
        (fun () ->
           Array.iteri (fun k ty -> encode st ctx slots structs texts k ty a.(k)) args;
           match ret with
           | Aggregate l ->
             let handle, block = new_block st ctx l.size in
             ffi_invoke cif address slots !structs block.address;
             rethrow st;
             handle
           | _ ->
             ffi_invoke cif address slots !structs 0;
             rethrow st;
             return_value ctx ret (Bytes.get_int64_ne slots (8 * n))))

(* Gives the address of a function to [f], or an Err if the library doesn't have it. *)
let with_symbol ctx name (lib : Types.t) f =
  match lib with
  | Handle { kind = "library"; id; _ } ->
    (match dlsym id name with
     | 0 -> Fs.failure ctx.w "c" (Messages.c_no_function name).text
     | address -> f address)
  | v -> Runtime.fail ctx Type (Messages.c_need_library (Value.describe v))

let bind st ctx (a : Types.t array) =
  let name = c_name ctx "Fn" a.(0) in
  let args = types_of st ctx a.(1) and ret = ty_of st ctx a.(2) in
  if Array.mem Void args then Runtime.fail ctx Type Messages.c_void_arg;
  let calls_back = Array.length a > 4 && a.(4) = True in
  let special = function Callback | Aggregate _ -> true | _ -> false in
  with_symbol ctx name a.(3) (fun address ->
      if Array.length args <= max_args && (not calls_back) && not (special ret || Array.exists special args) then
        Value.ok ctx.w (c_function st name address args ret)
      else begin
        ready st ctx;
        Value.ok ctx.w (ffi_function st ctx name address args ret (-1))
      end)

let variadic st ctx (a : Types.t array) =
  let name = c_name ctx "Variadic" a.(0) in
  let fixed = types_of st ctx a.(1) and rest = types_of st ctx a.(2) and ret = ty_of st ctx a.(3) in
  let total = Array.length fixed + Array.length rest in
  if total > max_ffi_args then Runtime.fail ctx Type (Messages.c_too_many total);
  Array.iter
    (function
      | I8 | U8 | I16 | U16 | Bool | F32 | Void | Callback | Aggregate _ as ty ->
        fail ctx (Messages.c_variadic_type (name_of ty))
      | _ -> ())
    rest;
  with_symbol ctx name a.(4) (fun address ->
      ready st ctx;
      Value.ok ctx.w (ffi_function st ctx name address (Array.append fixed rest) ret (Array.length fixed)))

let c_struct st ctx (a : Types.t array) : Types.t =
  ready st ctx;
  let fields = types_of st ctx a.(0) in
  if fields = [||] then fail ctx Messages.c_struct_empty;
  Array.iter
    (function
      | Text | Void | Callback as ty -> fail ctx (Messages.c_struct_field (name_of ty))
      | _ -> ())
    fields;
  let aligned at alignment = (at + alignment - 1) / alignment * alignment in
  let next = ref 0 in
  let offsets =
    Array.map
      (fun ty ->
         let at = aligned !next (alignment_of ty) in
         next := at + width ty;
         at)
      fields
  in
  let alignment = Array.fold_left (fun best ty -> max best (alignment_of ty)) 1 fields in
  let layout =
    { fields; offsets; size = aligned !next alignment; alignment;
      description = ffi_struct (Array.map (description st) fields) }
  in
  let id = Hashtbl.length st.layouts + 1 in
  Hashtbl.replace st.layouts id layout;
  Handle { kind = "ctype"; id; task = None }

let layout_arg st ctx name (v : Types.t) =
  match v with
  | Handle { kind = "ctype"; id; _ } -> Hashtbl.find st.layouts id
  | _ -> fail ctx (Messages.c_need_layout name (Value.describe v))

let c_offset st ctx (a : Types.t array) : Types.t =
  let l = layout_arg st ctx "c.Offset" a.(1) and k = Arrays.whole_index ctx a.(0) in
  if k < 1 || k > Array.length l.offsets then fail ctx (Messages.c_field_index k (Array.length l.offsets));
  Int l.offsets.(k - 1)

(* Runs in a context of its own: not a fiber, since a fiber's effects can't cross the C frames under it. A panic leaves
   a context in the middle of its frames, so it isn't used again. *)
let with_context st w f =
  let ctx = match st.spare with Some ctx -> ctx | None -> Runtime.create_ctx w in
  st.spare <- None;
  let r = f ctx in
  st.spare <- Some ctx;
  r

let c_callback st ctx (a : Types.t array) : Types.t =
  let f = a.(0) in
  (match f with
   | Fun _ | Native _ -> ()
   | v -> fail ctx (Messages.c_need_function (Value.describe v)));
  ready st ctx;
  let args = types_of st ctx a.(1) and ret = ty_of st ctx a.(2) in
  let plain = function Void | Callback | Aggregate _ -> false | _ -> true in
  Array.iter (fun ty -> if not (plain ty) then fail ctx (Messages.c_callback_type (name_of ty))) args;
  if ret <> Void && ((not (plain ret)) || ret = Text) then fail ctx (Messages.c_callback_type (name_of ret));
  let w = ctx.w in
  let entry arguments result =
    match
      with_context st w (fun inner ->
          let value k ty =
            let at = Int64.to_int (peek (arguments + (8 * k)) 8) in
            return_value inner ty (peek at (width ty))
          in
          let r = Compile.call_value inner ~base:0 f (Array.mapi value args) in
          if ret = Void then 0L else scalar st inner ret r)
    with
    | word -> poke result word
    | exception e ->
      st.pending <- Some e;
      poke result 0L
  in
  match ffi_closure (signature st ctx args ret (-1)) entry with
  | 0 -> fail ctx Messages.c_bad_signature
  | id -> Handle { kind = "callback"; id; task = None }

let offset_arg ctx ty (b : block) (v : Types.t) =
  match v with
  | Int o when o >= 0 && o <= b.size - width ty -> o
  | Int o -> fail ctx (Messages.c_offset o b.size (name_of ty))
  | _ -> fail ctx (Messages.c_need_offset (Value.describe v))

(* A type that a block can hold. Reading a pointer waits for an open library, as calling a function that gives one does. *)
let check_word st ctx verb ty =
  (match ty with
   | Text | Void | Callback | Aggregate _ -> fail ctx (Messages.c_block_type verb (name_of ty))
   | _ -> ());
  if ty = Ptr && not st.opened then fail ctx Messages.c_no_open_library

(* The same conversions as a call: a word read here is what a C function would have returned. *)
let get st ctx (a : Types.t array) =
  let ty = ty_of st ctx a.(0) in
  match a.(2) with
  | Handle { kind = "pointer"; id; _ } ->
    (* Memory that C gives, as the arguments of a comparison of qsort: its size is C's to know, as with ffi in all. *)
    check_word st ctx "read from" ty;
    (match a.(1) with
     | Int o when o >= 0 -> return_value ctx ty (peek (id + o) (width ty))
     | v -> fail ctx (Messages.c_need_offset (Value.describe v)))
  | _ ->
    let _, b = block_arg st ctx "Get" a.(2) in
    check_word st ctx "read from" ty;
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
  let ty = ty_of st ctx a.(0) in
  let _, b = block_arg st ctx "Set" a.(3) in
  check_word st ctx "written to" ty;
  let o = offset_arg ctx ty b a.(1) in
  let word = scalar st ctx ty a.(2) in
  (match width ty with
   | 1 -> b.data.{o} <- Char.chr (Int64.to_int word land 0xFF)
   | 2 -> set16 b.data o (Int64.to_int word)
   | 4 -> set32 b.data o (Int64.to_int32 word)
   | _ -> set64 b.data o word);
  Missing

(* Bytes between a text and a block, for what C treats as bytes: a text can hold zeros, and goes through whole. *)
let store st ctx (a : Types.t array) : Types.t =
  let s = Native.text_arg ctx "Store" a.(0) in
  let _, b = block_arg st ctx "Store" a.(2) in
  let at = Arrays.whole_index ctx a.(1) and n = String.length s in
  if at < 0 || at > b.size - n then fail ctx (Messages.c_offset at b.size "text");
  Runtime.pay_bytes ctx n;
  String.iteri (fun k ch -> b.data.{at + k} <- ch) s;
  Missing

let load st ctx (a : Types.t array) : Types.t =
  let _, b = block_arg st ctx "Load" a.(2) in
  let at = Arrays.whole_index ctx a.(0) and n = Arrays.whole_index ctx a.(1) in
  if n < 0 || at < 0 || at > b.size - n then fail ctx (Messages.c_offset at b.size "text");
  Runtime.pay_bytes ctx n;
  Types.Text (String.init n (fun k -> b.data.{at + k}))

let text st ctx (a : Types.t array) : Types.t =
  if not st.opened then fail ctx Messages.c_no_open_library;
  match a.(0) with
  | Handle { kind = "pointer"; id; _ } -> Types.Text (cstring id)
  | v -> fail ctx (Messages.c_need_pointer (Value.describe v))

let natives st =
  [ "Open", Native.nat ~result:true ~params:[| "name"; "version" |] "Open" 1 2 (open_library st);
    "Fn", Native.nat ~result:true ~params:[| "name"; "args"; "ret"; "lib"; "callsBack" |] "Fn" 4 5 (bind st);
    "Variadic", Native.nat "Variadic" 5 5 (variadic st);
    "Callback", Native.nat "Callback" 3 3 (c_callback st);
    "Struct", Native.nat "Struct" 1 1 (c_struct st);
    "Size", Native.nat "Size" 1 1 (fun ctx a -> Int (layout_arg st ctx "c.Size" a.(0)).size);
    "Offset", Native.nat "Offset" 2 2 (c_offset st);
    "Alloc", Native.nat "Alloc" 1 1 (alloc st);
    "Free", Native.nat "Free" 1 1 (free st);
    "Get", Native.nat "Get" 3 3 (get st);
    "Store", Native.nat "Store" 3 3 (store st);
    "Load", Native.nat "Load" 3 3 (load st);
    "Set", Native.nat "Set" 4 4 (set st);
    "Text", Native.nat "Text" 1 1 (text st) ]
