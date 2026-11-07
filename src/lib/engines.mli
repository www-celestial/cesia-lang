(** Native packages: the natives of the package that the [native] of a cesia.toml names, as stubs that load its engine at
    the first call of one of them, and what Cesia_v1 asks of the engine. *)
open Types

(** A native of an engine: name, fewest and most arguments, code. *)
type native = string * int * int * (ctx -> t array -> t)

(** Set by the binary: the tag of the engines it loads, as 1-ocaml5.5.0+fp-linux-x86_64; and how it loads one, the plugin of
    Cesia_v1 first, then the engine, strictly checked. *)
val suffix : (unit -> string) ref

val loader : (string -> (unit, string) result) ref

(** Cesia_v1.register: the natives of the engine that is loading, once. *)
val register : native list -> unit

(** Is it an exception of Cesia's own, which crosses a native untouched? *)
val own : exn -> bool

(** The stubs of the natives of the package in this folder, from the top of the file system, if a [native] names it. *)
val natives : world -> string -> (string * t) list option

(** [cesia.Native]: the tag of the engines this Cesia loads. *)
val cesia : (string * t) list
