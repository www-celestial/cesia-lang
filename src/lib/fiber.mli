(** Fibers: a FIFO scheduler on OCaml effects, with one [ctx] per fiber. The main program isn't a fiber: it runs the
    scheduler whenever it waits, and the other fibers are dropped when it ends. *)
open Types

(** Parks the current fiber and calls [register resume]. Calling [resume] once puts it back in the queue. *)
val suspend : ctx -> ((unit -> unit) -> unit) -> unit

(** Lets the other fibers run, if there are any. *)
val yield : ctx -> unit

(** The natives of std/fiber: [Spawn], [Wait] and the channels. *)
val natives : (string * t) list

(** Starts a function in a new fiber: gives its task, which [wait] waits for. *)
val spawn : ctx -> t -> t

(** Waits for a task to end: gives its result, an Ok of its value or an Err of its panic; with a timeout in seconds, an
    Err of the kind "timeout" if it hasn't ended by then. *)
val wait : ?timeout:float -> ctx -> t -> t
