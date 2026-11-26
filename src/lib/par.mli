(** Several cores for work on whole columns: small work stays on one, because starting a core has a cost. By default, half
    of the logical cores: floating point work gains nothing from a core's second thread. [CESIA_CORES] sets the number. The
    work must not touch the state of the program, nor panic. *)

val cores : unit -> int

(** Joins a domain. Its end emptied the young heap of every domain, and in OCaml 5.5 that runs no slice of the major GC,
    which the main domain asks for only when half its young heap is used: never, when domains end more often, and the
    heap kept all that their ends promoted. Here comes the slice that half a young heap of allocation asks for. *)
val join : unit Domain.t -> unit

(** The slice of [join] alone, for the end of a job on a domain that goes on. *)
val pace : unit -> unit

(** Runs [f 0] to [f (n - 1)], each on its own core. *)
val each : int -> (int -> unit) -> unit

(** Cuts the positions from 0 to [n] into one range per core, of at least [grain] positions, and runs [f low high] on
    each. Below two grains, it runs on the calling core. *)
val ranges : ?grain:int -> int -> (int -> int -> unit) -> unit
