(** Generic arithmetic: numbers, booleans, [missing]. *)
open Types

val add_int : ctx -> int -> int -> int
val sub_int : ctx -> int -> int -> int
val mul_int : ctx -> int -> int -> int
val add : ctx -> t -> t -> t
val sub : ctx -> t -> t -> t
val mul : ctx -> t -> t -> t
val div : ctx -> t -> t -> t
val pow : ctx -> t -> t -> t
val neg : ctx -> t -> t
val lt : ctx -> t -> t -> t
val le : ctx -> t -> t -> t
val gt : ctx -> t -> t -> t
val ge : ctx -> t -> t -> t
val eq : ctx -> t -> t -> t
val ne : ctx -> t -> t -> t
val int_div : ctx -> int -> int -> int
val int_mod : ctx -> int -> int -> int

(** Applies an operation element by element: scalar or array of the same shape. *)
val broadcast : ctx -> (ctx -> t -> t -> t) -> t -> t -> t
