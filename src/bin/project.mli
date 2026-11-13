(** cesia do: reads cesia.toml from the current folder, checks it, and lists or runs its tasks. *)

(** Takes the words after [do], and ends the program. *)
val run : string list -> unit

(** cesia new: a folder with its cesia.toml, .gitignore, src/main.ce and an empty std/, which the pkg tool then fills. *)
val create : string -> unit

(** What [test] of cesia.toml says: the permissions a test gets beyond its defaults, the seconds it may take ("10" by
    default, as a text), the files and folders that share a resource, which run alone, and those that cesia test leaves
    out unless its path is in one of them. *)
type test = { allow : string list; timeout : float; serial : string list; skip : string list }

(** [test] of the cesia.toml at a root, or its defaults without one; a wrong value stops the program. *)
val test_config : string -> test
