(** cesia do: reads cesia.toml from the current folder, checks it, and lists or runs its tasks. *)

(** Takes the words after [do], and ends the program. *)
val run : string list -> unit

(** cesia new: a folder with a cesia.toml and a main.ce, and ends the program. *)
val create : string -> unit
