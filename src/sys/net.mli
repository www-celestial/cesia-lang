(** TCP sockets for fibers: a call that waits suspends only its fiber. *)
open Cesia

type t

val create : Poll.t -> t

(** Finds the address of a name, or raises [Not_found]. It may block: it doesn't run on the fibers' domain. *)
val resolver : (string -> Unix.inet_addr) ref

(** Did a stop signal arrive? *)
val stopping : t -> bool

(** The stop signals end the program at once, once passed on to the processes it started: for a program that starts
    some, and doesn't serve. *)
val follow : t -> unit

(** A window takes the stop signals with [true], and leaves them with [false]. Taken before SDL starts, they stay
    Cesia's: SDL leaves alone a signal that has a handler, and makes no quit event for it. *)
val take_stops : t -> bool -> unit

(** Did a stop signal arrive since this was last asked, with a window to hear of it? *)
val stop_asked : t -> bool

(** Closes every socket and forgets the listeners: a test ended. *)
val reset : t -> unit

(** The contents of the [net] module. *)
val natives : t -> (string * Types.t) list

(** The natives that only the files of std/http see: the deadlines of the sockets it serves, and its check of a header
    line. *)
val http_natives : t -> (string * Types.t) list
