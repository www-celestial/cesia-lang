(** TCP sockets for fibers: a call that waits suspends only its fiber. *)
open Kepler

type t

val create : Poll.t -> t

(** Finds the address of a name, or raises [Not_found]. It may block: it doesn't run on the fibers' domain. *)
val resolver : (string -> Unix.inet_addr) ref

(** Did a stop signal arrive? *)
val stopping : t -> bool

(** A window takes the stop signals with [true], and leaves them with [false]. Taken before SDL starts, they stay
    Kepler's: SDL leaves alone a signal that has a handler, and makes no quit event for it. *)
val take_stops : t -> bool -> unit

(** Did a stop signal arrive since this was last asked, with a window to hear of it? *)
val stop_asked : t -> bool

(** The contents of the [net] module. *)
val natives : t -> (string * Types.t) list
