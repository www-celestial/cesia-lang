(** Native functions and the constants of the prelude. *)
open Types

val prelude : (string * t) list

(** Adds a native to the prelude. Used by tests. *)
val register : world -> string -> t -> unit

(** The byte where [part], which isn't empty, first appears in a text from a byte, or -1. *)
val find_from : string -> string -> int -> int

(** The number that a text writes, or [missing]. *)
val number : string -> t

(** The code points of a text. *)
val code_points : string -> int

(** The code points in the bytes of a text from a position up to another, excluded. *)
val points_between : string -> int -> int -> int

(** The text of an argument, or a [type] panic naming the function. *)
val text_arg : ctx -> string -> t -> string

(** A native: name, minimum and maximum argument count, code. *)
val nat :
  ?perm:perm -> ?params:string array -> ?ret:(ty array -> ty) -> string -> int -> int ->
  (ctx -> t array -> t) -> t
