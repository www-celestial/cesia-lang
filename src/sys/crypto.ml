open Cesia
open Types

(* The BLAKE2b of OCaml's runtime, which its Stdlib's Digest.BLAKE256 calls: the reference code of RFC 7693, with the size
   of the hash, 1 to 64 bytes, in its parameters as libsodium's crypto_generichash has it, so the same bytes. Its Stdlib
   names only the sizes 16, 32 and 64; this is the same primitive, given the size, without a key. A call through std/c
   took 18.5 µs for 64 bytes; this one 0.31. *)
external blake2 : int -> string -> string -> int -> int -> string = "caml_blake2_string"

let blake2b ctx (a : t array) =
  let s = Native.text_arg ctx "blake2b" a.(0) and size = Native.dim ctx "blake2b" a.(1) in
  if size < 16 || size > 64 then Runtime.fail ctx Type Messages.blake2b_size;
  Runtime.pay_bytes ctx (String.length s);
  Text (blake2 size "" s 0 (String.length s))

let same_bytes x y =
  String.length x = String.length y
  &&
  let d = ref 0 in
  for i = 0 to String.length x - 1 do
    d := !d lor (Char.code x.[i] lxor Char.code y.[i])
  done;
  !d = 0

let natives =
  [ "blake2b", Native.nat "blake2b" 2 2 blake2b;
    "isSame", Native.nat "isSame" 2 2 (fun ctx a ->
        Value.of_bool (same_bytes (Native.text_arg ctx "IsSame" a.(0)) (Native.text_arg ctx "IsSame" a.(1)))) ]
