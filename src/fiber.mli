(** Fibers: a FIFO scheduler on OCaml effects, with one [ctx] per fiber. The main program isn't a fiber: it runs the
    scheduler whenever it waits, and the other fibers are dropped when it ends. *)
open Types

(** Starts a function in a new fiber and returns its task. *)
val spawn : ctx -> t -> t

(** Suspends until a task ends: [Ok(value)], or [Err(e)] if it panicked. *)
val wait : ctx -> t -> t

(** Parks the current fiber and calls [register resume]. Calling [resume] once puts it back in the queue. *)
val suspend : ctx -> ((unit -> unit) -> unit) -> unit

(** Lets the other fibers run, if there are any. *)
val yield : ctx -> unit

(** [spawn] and [wait], for the prelude. *)
val natives : (string * t) list
