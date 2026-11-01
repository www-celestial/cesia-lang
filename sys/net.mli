(** TCP sockets for fibers: a call that waits suspends only its fiber. *)
open Kepler

type t

val create : Poll.t -> t

(** Did a stop signal arrive? *)
val stopping : t -> bool

(** The contents of the [net] module. *)
val natives : t -> (string * Types.t) list
