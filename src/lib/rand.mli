(** Random numbers, for std/random: SplitMix64, the same numbers for a seed on every version and system. *)
open Types

(** Sets the seed of the process, as cesia run --seed does. Without it, the first draw takes one from the system. *)
val set_seed : int -> unit

(** The seed of this run: the one given, or the one taken from the system. *)
val seed : unit -> int

(** The natives of std/random: Int, Float and Seed. *)
val natives : (string * t) list
