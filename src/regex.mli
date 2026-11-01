(** The regex module: a Pike machine, so the time stays linear in the text whatever the pattern, and a hostile input
    can't stall a server. *)
open Types

(** The natives, around a cache of compiled patterns. *)
val natives : unit -> (string * t) list
