(** Natives of the prelude for lists and texts: no parsing cost at start, unlike the prelude in Cesia. *)
open Types

val natives : (string * t) list
