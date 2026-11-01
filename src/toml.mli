(** The reader of kepler.toml: a strict subset of TOML 1.0. A file it accepts means the same in any TOML reader, and
    anything else is an error on its line, never a guess. *)

type value = Text of string | Flag of bool | Texts of string list
type entry = { key : string; value : value; line : int }

(** [path] is empty for the keys before any header. [start] is the line of the header. *)
type table = { path : string list; start : int; entries : entry list }

(** Tables in the order of the file, entries in the order of their table. Never raises. *)
val parse : string -> (table list, int * string) result
