(** Fibers: a FIFO scheduler on OCaml effects, with one [ctx] per fiber. The main program isn't a fiber: it runs the
    scheduler whenever it waits, and the other fibers are dropped when it ends. *)
open Types

(** Parks the current fiber and calls [register resume]. Calling [resume] once puts it back in the queue; later calls do
    nothing. *)
val suspend : ctx -> ((unit -> unit) -> unit) -> unit

(** Lets the other fibers run, if there are any. *)
val yield : ctx -> unit

(** The next value of a channel, waiting for it, or None once it is closed and empty: [world.next_in]. *)
val next_in : ctx -> t -> t option

(** The natives of std/fiber: [Spawn], [Wait], [Cancel] and the channels: [Channel], [Send], [Receive], [Select], [Close]. *)
val natives : (string * t) list

(** Starts a function in a new fiber: gives its task, which [wait] waits for. *)
val spawn : ctx -> t -> t

(** Waits for a task to end: gives its result, an Ok of its value or an Err of its panic; with a timeout in seconds, an
    Err of the kind "timeout" if it hasn't ended by then. *)
val wait : ?timeout:float -> ctx -> t -> t
