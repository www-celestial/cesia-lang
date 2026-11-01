(** Natives of the prelude for lists and texts: no parsing cost at start, unlike the prelude in Kepler. *)
open Types

val natives : (string * t) list
