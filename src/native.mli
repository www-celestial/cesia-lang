(** Native functions and the constants of the prelude. *)
open Types

val prelude : (string * t) list

(** Adds a native to the prelude. Used by native modules and tests. *)
val register : world -> string -> t -> unit

(** A native: name, minimum and maximum argument count, code. *)
val nat :
  ?perm:perm -> ?params:string array -> ?ret:(ty array -> ty) -> string -> int -> int ->
  (ctx -> t array -> t) -> t
