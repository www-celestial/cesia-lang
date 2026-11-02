(** The [c] module: calling C libraries from Kepler. A granted library is total trust. Without one, a program can't reach
    any memory outside its own blocks. *)

type t

val create : unit -> t
val natives : t -> (string * Kepler.Types.t) list
