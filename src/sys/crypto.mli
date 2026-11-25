(** The natives of std/crypto that need no libsodium: BLAKE2b by OCaml's runtime, and a comparison of two texts in a time
    that doesn't tell where they differ. *)

(** [same_bytes x y]: do two texts hold the same bytes? Every byte is read, whatever they hold, and their differences
    gathered by or, with no branch on them, as eqaf of MirageOS does in OCaml. Texts of two lengths differ at once, as with
    libsodium's sodium_memcmp, which takes one length: a length is no secret. *)
val same_bytes : string -> string -> bool

(** blake2b(text, size) and isSame(a, b), which only std/crypto sees. *)
val natives : (string * Cesia.Types.t) list
