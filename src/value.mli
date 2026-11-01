(** Values: errors, printing, equality. *)
open Types

exception Kerr of { kind : kind; text : string; hint : string option; at : int }

(** A limit reached. Nothing in the language catches it. *)
exception Limit of { what : string; at : int }

val of_bool : bool -> t

(** Clears [owned] and returns the value: a second reference is about to lead to it. *)
val share : t -> t

(** Element [k] of an array, from 0, in column order. *)
val elt : arr -> int -> t
val kind_name : kind -> string
val float_text : float -> string

(** The shape of these fields. Two identical requests return the same shape. *)
val shape_of : world -> ?sname:string -> string array -> shape

(** The position of a field, or -1. *)
val field_index : shape -> string -> int

(** A new struct with one more field. *)
val add_field : world -> shape -> t array -> string -> t -> t

(** The results of the prelude: [Ok(v)] and [Err(v)]. *)
val ok : world -> t -> t

val err : world -> t -> t

(** An [Err] of a value with a kind and a message. *)
val failure : world -> string -> string -> t

(** The value written as code. *)
val show : ctx -> t -> string

(** Like [show], but a text stays raw: what [print] and [text] display. *)
val text_of : ctx -> t -> string

(** How a message names a value: [the text "a"], [the number 1]. *)
val describe : t -> string

(** Equality of whole values: [equal nan nan] is true. *)
val equal : ctx -> t -> t -> bool

(** Folds a dictionary from its last key to its first. *)
val dict_fold : (t -> t -> 'a -> 'a) -> dict -> 'a -> 'a
