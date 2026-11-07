(** The module [cesia], for the tools of [src/tools/]: this Cesia's version and libraries, fingerprints, and readers of
    cesia.toml and of the uses of a source. *)
open Types

(** The natives of the module, given the libraries of this Cesia, names and sources. *)
val natives : libraries:(unit -> (string * string) list) -> (string * t) list
