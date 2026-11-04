(** cesia do: reads cesia.toml from the current folder, checks it, and lists or runs its tasks. *)

(** Takes the words after [do], and ends the program. *)
val run : string list -> unit

(** cesia new: a folder with its cesia.toml, .gitignore, src/main.ce and an empty pkg/, which the pkg tool then fills. *)
val create : string -> unit
