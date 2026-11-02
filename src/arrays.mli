(** Arrays: construction, indexing, writing. *)
open Types

type ix = At of int | Slice of int * int | Every | Mask of arr | Key of t

val of_float : int -> int -> floatarray -> t

(** Stores as F if everything is a float. *)
val of_vals : int -> int -> t array -> t
val of_ints : int -> int -> int array -> t

(** A list. An empty one has the shape of [[]], so that the two are equal. *)
val list : t array -> t

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
