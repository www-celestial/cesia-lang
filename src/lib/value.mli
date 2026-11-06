(** Values: errors, printing, equality. *)
open Types

exception Kerr of { kind : kind; text : string; hint : string option; at : int }

(** A limit reached. Nothing in the language catches it. *)
exception Limit of { what : string; at : int }

(** sys.Exit: the program ends here, with this code. *)
exception Quit of int

val of_bool : bool -> t

(** The array, with its store cut to its cells. See [arr]. *)
val trim : arr -> arr

(** Clears [owned] and returns the value: a second reference is about to lead to it. *)
val share : t -> t

(** Element [k] of an array, from 0, in column order. *)
val elt : arr -> int -> t
val kind_name : kind -> string
val float_text : float -> string

(** The module of the shape of a struct of this name declared in module [m]: [Ok] and [Err] have one for everyone. *)
val struct_module : string -> int -> int

(** The shape of these fields. Two identical requests return the same shape. *)
val shape_of : world -> ?sname:string -> ?m:int -> string array -> shape

(** The position of a field, or -1. *)
val field_index : shape -> string -> int

(** The results of the prelude: [Ok(v)] and [Err(v)]. *)
val ok : world -> t -> t

val err : world -> t -> t

(** An [Err] of a value with a kind and a message. *)
val failure : world -> string -> string -> t

(** The value written as code. *)
val show : ctx -> t -> string

(** Like [show], but a text stays raw: what [Print] and [Text] display. *)
val text_of : ctx -> t -> string

(** How a message names a value: [the text "a"], [the number 1]. *)
val describe : t -> string

(** How a type error names the kind of a value: [an Int], [a Rect], [missing]. *)
val type_of : t -> string

(** Equality of whole values: [equal nan nan] is true. *)
val equal : ctx -> t -> t -> bool

(** The keys and values of a map, k1 v1 k2 v2..., in the order of insertion; [||] for another value. Read only. *)
val items : t -> t array
