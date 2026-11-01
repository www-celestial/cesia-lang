(** [kepler test]: the doc comment examples and the [is_*] functions. *)
open Types

(** Returns the exit code. *)
val run : world -> path:string -> int
