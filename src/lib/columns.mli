(** The [columns] module: work on whole columns in OCaml, for tables of millions of rows. *)
open Types

val natives : (string * t) list

(** Natives that only the prelude sees: [groupIds(keys)], the groups of keys as [Equal] makes them; [groupParts(g, xs)],
    the values of each group, missing ones too; [frequencies(xs)], what the loop of [Frequencies] gives, or missing. *)
val prelude : (string * t) list

(** The keys of rows with these names, made public names if asked, or why they can't be: two names give one key. Equal lists
    share their keys. *)
val row_keys : bool -> string array -> (keys, string) result

(** A list of maps with these keys, from cells given row after row. *)
val make_rows : ctx -> keys -> t array -> t
