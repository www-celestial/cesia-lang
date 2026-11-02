(** Dictionaries: persistent balanced trees, so a change gives a new value and a copy costs nothing. Keys are numbers or
    texts, and stay in order. *)
open Types

(** The order of keys. *)
val compare_keys : t -> t -> int

(** Can this value be a key? *)
val is_key : t -> bool

val length : dict -> int

(** The value of a key. A key of the wrong kind is a panic. *)
val find : ctx -> t -> dict -> t option

val add : ctx -> t -> t -> dict -> dict
val remove : ctx -> t -> dict -> dict
