(** Several cores for work on whole columns: small work stays on one, because starting a core has a cost. By default, half
    of the logical cores: floating point work gains nothing from a core's second thread. [CESIA_CORES] sets the number. The
    work must not touch the state of the program, nor panic. *)

val cores : unit -> int

(** Runs [f 0] to [f (n - 1)], each on its own core. *)
val each : int -> (int -> unit) -> unit

(** Cuts the positions from 0 to [n] into one range per core, of at least [grain] positions, and runs [f low high] on
    each. Below two grains, it runs on the calling core. *)
val ranges : ?grain:int -> int -> (int -> int -> unit) -> unit
