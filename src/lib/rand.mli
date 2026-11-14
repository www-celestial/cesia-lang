(** Random numbers, for std/random: SplitMix64, the same numbers for a seed on every version and system. *)
open Types

(** Sets the seed of the process, as cesia run --seed does. Without it, the first draw takes one from the system. *)
val set_seed : int -> unit

(** The seed of this run: the one given, or the one taken from the system. *)
val seed : unit -> int

(** Starts the numbers of a run again from the seed, so that the same seed gives the same numbers whatever ran before. *)
val reset : unit -> unit

(** Starts the numbers again from a state made of the seed of the run and names, keeping the seed: cesia test gives each
    test its own, from its file and name, std/cells each cell, from its title. *)
val restart : string list -> unit

(** From 0 to [n] - 1, for [n] > 0, without bias: what std/gen draws. *)
val below : int -> int

(** The natives of std/random: Int, Float and Seed. *)
val natives : (string * t) list

(** The native of std/num that draws: uniform(n), the n floats of num.Uniform, those of n calls of Float in turn. *)
val num : (string * t) list
