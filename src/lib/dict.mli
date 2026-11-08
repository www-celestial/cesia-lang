(** Maps, as the program sees them: the functions of [Trie] with the checks of keys and the messages. Keys are numbers or
    texts; a map never changes, a change gives a new one. Also a balanced tree used as a set. *)
open Types

(** The order of keys in a tree. *)
val compare_keys : t -> t -> int

(** Can this value be a key? *)
val is_key : t -> bool

(** Panics when the value can't be a key. *)
val check : ctx -> t -> unit

(** The value of a key in a tree used as a set. A key of the wrong kind is a panic. *)
val find : ctx -> t -> dict -> t option

(** A key in a tree used as a set, without order. *)
val add : ctx -> t -> t -> dict -> dict

(** An empty map. *)
val empty : unit -> t

(** A map of the keys and values k1 v1 k2 v2...: a later key replaces the value and keeps the place. *)
val of_items : ctx -> t array -> t

(** In the functions below, [name] is the function that a message names when the value is no map. *)

(** The value of a key, or [None]. *)
val get : ctx -> string -> t -> t -> t option

(** [put ctx name k v m]: the map with [k] set to [v]. *)
val put : ctx -> string -> t -> t -> t -> t

(** The map without that key. *)
val drop : ctx -> string -> t -> t -> t

(** The keys and values of a map, k1 v1 k2 v2..., in the order of insertion. Read only. *)
val items : ctx -> string -> t -> t array
