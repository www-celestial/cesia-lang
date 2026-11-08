(** The storage of maps: one hash trie, as Clojure's. Up to 32 keys a map is one block, its keys in the order of insertion
    beside their hashes and its values; past them the block splits by 5 bits of hash into a branch of blocks of the same
    kind. Keys of equal hashes go to a balanced tree, which no choice of keys slows down. The hash takes a seed drawn once per
    run. Keys are numbers or texts; [1] and [1.0] are one key. Nothing here checks the kind of a key: [Dict] does. *)
open Types

(** The [order] of a deep map that wasn't asked yet. *)
val no_order : t array

(** The most keys of a block. *)
val width : int

(** The hash of a key. *)
val hash : t -> int

(** [hash (Int i)], [hash (Float f)] and [hash (Text s)], without the box. *)
val hash_int : int -> int
val hash_float : float -> int
val hash_text : string -> int

(** For tests only: [0] sends every key to one hash. *)
val mask : int ref

(** The rank at which a deep map renumbers its ranks in its order; 2^32, smaller in tests. *)
val rank_limit : int ref

(** The order of keys in a tree. *)
val compare_keys : t -> t -> int

(** Is it the same key? *)
val same : t -> t -> bool

(** Marks a value as held in two places: a write to it must copy it first. *)
val share : t -> t

(** No keys. *)
val no_keys : keys

(** These names as text keys, with their hashes. *)
val names : string array -> keys

(** An empty map. *)
val empty : unit -> t

(** A map of one block: at most [width] keys, each once, and their values. *)
val record : keys -> t array -> t

(** [index keys n h k]: the place of [k], of hash [h], among the first [n] keys, or -1. *)
val index : keys -> int -> int -> t -> int

(** Keys made whole: every map that holds them has all of them, so a read can cache their places. *)
val is_whole : keys -> bool

(** [extend keys n k h]: whole keys, the first [n] of [keys] and [k]. *)
val extend : keys -> int -> t -> int -> keys

(** [find m h k]: the value of [k], of hash [h], or [Undef]. *)
val find : t -> int -> t -> t

(** The values of a map of one block: [F] while every one is a float, [V] otherwise; [no_vals] of an empty or deep map. *)
val no_vals : store

(** The number of values of a store. *)
val nvals : store -> int

(** The value at a place of a store. *)
val vget : store -> int -> t

(** The store of these values: [F] when they are floats, else [V] of this array. *)
val vals_of : t array -> store

(** [vals_of] of two, three or four values, without an array between. *)
val vals2 : t -> t -> store

val vals3 : t -> t -> t -> store
val vals4 : t -> t -> t -> t -> store

(** The values as an array: the [V] store's own, or a new one. *)
val vals_array : store -> t array

(** [vset m i x]: value [i] of the owned map [m] of one block set in place; [x] not a float turns an [F] store into [V]. *)
val vset : t -> int -> t -> unit

(** The values and one more at their end, a new store. *)
val vappend : store -> t -> store

(** The number of keys of a map. *)
val length : t -> int

(** [put m h k v]: a new map with [k] set to [v]; a key that is there keeps its place. [m] doesn't change. *)
val put : t -> int -> t -> t -> t

(** The same for a map that nothing else holds: it changes in place, or gives the map that takes its place. *)
val put_owned : t -> int -> t -> t -> t

(** [put_owned] for a key that a map of one block is known to lack. *)
val add_absent : t -> int -> t -> t -> t

(** A copy of a map that someone else holds too, owned: O(1) for a deep map, whose writes then copy the nodes they change. *)
val own_copy : t -> t

(** A new map without that key, or the same map. *)
val drop : t -> int -> t -> t

(** The keys and values, k1 v1 k2 v2..., in the order of insertion. Read only. *)
val items : t -> t array

(** A map of k1 v1 k2 v2...: a later key replaces the value and keeps the place. With the same keys as [like], in the same
    order and written alike, the map shares them. *)
val of_items : ?like:keys -> t array -> t

(** The keys of a map of one block, or [no_keys]. *)
val keys_of_map : t -> keys

(** The tree, for sets: a key that is there keeps its rank. *)
val tree_insert : t -> t -> int -> dict -> dict

(** The value of a key in a tree, or [Undef]. *)
val tree_find : t -> dict -> t
