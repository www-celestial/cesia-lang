(** Arrays: construction, indexing, writing. *)
open Types

type ix = At of int | Slice of int * int | Every | Mask of arr | Key of t

val of_float : int -> int -> floatarray -> t

(** Stores as F if everything is a float. *)
val of_vals : int -> int -> t array -> t
val of_ints : int -> int -> int array -> t

(** A list. An empty one has the shape of [[]], so that the two are equal. *)
val list : t array -> t

(** A list built one value at a time, with the store that [of_vals] would give it: floats and integers without a box. The
    [int] is the site of the list: when it grows, it reserves memory there. *)
type builder

val builder : unit -> builder
val add : ctx -> int -> builder -> t -> unit
val add_float : ctx -> int -> builder -> float -> unit
val add_int : ctx -> int -> builder -> int -> unit

(** The values added, as a list of 1 x n. *)
val built : builder -> t

val int_range : ctx -> int -> int -> t
val range_bound : ctx -> t -> int
val ix_of : ctx -> t -> ix
val mem : ctx -> t -> t -> t
val positions : ctx -> int -> ix -> int array
val pick : ctx -> arr -> int array -> int -> int -> t
val read1 : ctx -> t -> ix -> t
val read2 : ctx -> t -> ix -> ix -> t
val write : ctx -> t -> ix array -> t -> unit

(** Reads with one or two indexes. *)
val read : ctx -> t -> ix array -> t

(** Writes element [k], from 0, in an owned array. The first [int] is the site, for the slow path that converts
    the storage. *)
val store_elt : ctx -> int -> arr -> int -> t -> unit

(** An index: an integer, or a float with an integer value. *)
val whole_index : ctx -> t -> int

(** The key of an index on a dictionary. *)
val key_of : ctx -> ix array -> t
