(** kepler do: reads kepler.toml from the current folder, checks it, and lists or runs its tasks. *)

(** Takes the words after [do], and ends the program. *)
val run : string list -> unit

(** kepler new: a folder with a kepler.toml and a main.k, and ends the program. *)
val create : string -> unit
