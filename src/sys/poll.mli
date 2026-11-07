(** Parks fibers on descriptors and timers, and wakes them when nothing else can run. *)
open Cesia
open Types

type t

val create : unit -> t

(** Starts watching a descriptor, in non-blocking mode. *)
val watch : t -> Unix.file_descr -> unit

(** Stops watching it, before it is closed, and wakes the fibers waiting on it. *)
val forget : t -> Unix.file_descr -> unit

(** Suspend the fiber until the descriptor may be ready. The fiber then tries its operation again. *)
val read_ready : t -> ctx -> Unix.file_descr -> unit

val write_ready : t -> ctx -> Unix.file_descr -> unit

(** Suspends the fiber until any of these may be ready. *)
val any_ready : t -> ctx -> read:Unix.file_descr list -> write:Unix.file_descr list -> unit

(** Suspends the fiber for this many seconds. 0 lets every ready fiber run first. *)
val sleep : t -> ctx -> float -> unit

(** Calls a function after this many seconds, from the scheduler. Gives the function that cancels it: a wait that ends
    first leaves no timer behind. *)
val timer : t -> float -> (unit -> unit) -> unit -> unit

(** Wakes the fibers whose descriptor or timer is ready, blocking until one is if asked: the value of [world.idle].
    Returns false when nothing is being waited for. *)
val idle : t -> bool -> bool

(** Calls a function at least every [period] seconds while the program is blocked. *)
val set_tick : t -> float -> (unit -> unit) -> unit

(** Says that a stop signal arrived. Safe in a signal handler: every reader wakes at the next pass. *)
val interrupt : t -> unit

(** Forgets every fiber parked on a descriptor or a timer: a test ended, and its fibers with it. *)
val reset : t -> unit
