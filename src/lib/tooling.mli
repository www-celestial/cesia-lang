(** The module [cesia], for the tools of [src/tools/]: this Cesia's version and libraries, fingerprints, and readers of
    cesia.toml and of the uses of a source. *)
open Types

(** [blake2:] and the 64 hexadecimal digits of the BLAKE2b-256 of a text. *)
val fingerprint : string -> string

(** The natives of the module, given the libraries of this Cesia, names and sources. *)
val natives : libraries:(unit -> (string * string) list) -> (string * t) list
