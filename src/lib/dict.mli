(** Maps. Keys fixed by the code make a struct without a name; keys from data, a persistent balanced tree, sorted by key for
    the search, so that a change gives a new value and a copy costs nothing. Each key of a tree holds its rank, so both keep
    the order of insertion. Keys are numbers or texts. *)
open Types

(** The order of keys in a tree. *)
val compare_keys : t -> t -> int

(** Can this value be a key? *)
val is_key : t -> bool

val length : dict -> int

(** The value of a key in a tree. A key of the wrong kind is a panic. *)
val find : ctx -> t -> dict -> t option

(** A key in a tree used as a set, without order. *)
val add : ctx -> t -> t -> dict -> dict

(** The most keys of a map with a shape: past them, a tree. *)
val most : int

(** An empty map, in a tree. *)
val empty : t

(** A map in a tree of the keys and values k1 v1 k2 v2..., which it keeps: a later key replaces the value and keeps the place. *)
val of_items : ctx -> t array -> t

(** In the functions below, [name] is the function that a message names when the value is no map. *)

(** The value of a key, or [None]. *)
val get : ctx -> string -> t -> t -> t option

(** [put ctx name k v m]: the map with [k] set to [v]. A new key of a struct without a name gives a tree. *)
val put : ctx -> string -> t -> t -> t -> t

(** The map without that key. *)
val drop : ctx -> string -> t -> t -> t

(** [m.name = x] or [m["name"] = x] written in the code: a name that [m] doesn't have gives a new shape while there are few,
    else a tree. *)
val add_name : ctx -> t -> string -> t -> t

(** The keys and values of a map, k1 v1 k2 v2..., in the order of insertion. Read only. *)
val items : ctx -> string -> t -> t array
