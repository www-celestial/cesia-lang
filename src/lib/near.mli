(** math.Near, and where two values first differ, for the failures of tests. *)
open Types

(** A tolerance: [rel] of the larger magnitude, or [abs], whichever is larger. *)
type tol = { rel : float; abs : float }

(** Where two values first differ, from the outside in: the path ([[2].Tax], [""] for the values themselves) and the two values
    there, or [None] when they are equal, or near within [tol] if given. *)
val first : ctx -> ?tol:tol -> t -> t -> (string * t * t) option

(** The tolerance of a call to math.Near, from its [rel] and [abs] arguments, [Undef] when absent. *)
val tol_of : ctx -> t -> t -> tol

(** The natives of std/math that live here: Near. *)
val natives : (string * t) list
