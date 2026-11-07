(** A growable array, as the Stdlib's Dynarray, which would link OCaml's runtime of objects into the binary: its frame
    tables cost every start-up. [get] and [set] past the end raise [Invalid_argument]. [clear] keeps the room. *)
type 'a t

val create : unit -> 'a t
val length : 'a t -> int
val get : 'a t -> int -> 'a
val set : 'a t -> int -> 'a -> unit
val get_last : 'a t -> 'a
val add_last : 'a t -> 'a -> unit
val clear : 'a t -> unit
val to_array : 'a t -> 'a array
val to_list : 'a t -> 'a list
val iter : ('a -> unit) -> 'a t -> unit
