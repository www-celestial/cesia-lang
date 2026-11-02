(** TCP sockets for fibers: a call that waits suspends only its fiber. *)
open Kepler

type t

val create : Poll.t -> t

(** Finds the address of a name, or raises [Not_found]. It may block: it doesn't run on the fibers' domain. *)
val resolver : (string -> Unix.inet_addr) ref

(** Did a stop signal arrive? *)
val stopping : t -> bool

(** The contents of the [net] module. *)
val natives : t -> (string * Types.t) list
