(** The [columns] module: work on whole columns in OCaml, for tables of millions of rows. *)
open Types

val natives : (string * t) list

(** Natives that only the prelude sees: [groupIds(keys)], the groups of keys as [Equal] makes them; [groupParts(g, xs)],
    the values of each group, missing ones too; [frequencies(xs)], what the loop of [Frequencies] gives, or missing. *)
val prelude : (string * t) list
