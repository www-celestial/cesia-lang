(** Native functions and constants, in the packages of std/ that they belong to. *)
open Types

(** The dictionary literal, which only the parser writes, and so the only name the compiler finds without a use. *)
val core : (string * t) list

(** Each package of std/ with its natives: a small first letter, as [merge], stays inside the package. *)
val packages : (string * (string * t) list) list

(** What value.Len counts, but for a struct that says it: the elements of an array, the code points of a text, the keys of a
    map, the fields of a struct; 1 for anything else. *)
val length : t -> int

(** The byte where [part], which isn't empty, first appears in a text from a byte, or -1; with [fold], ASCII letters match
    in either case. *)
val find_from : ?fold:bool -> string -> string -> int -> int

(** The number that a text writes, or [missing]. *)
val number : string -> t

(** The code points of a text. *)
val code_points : string -> int

(** The code points in the bytes of a text from a position up to another, excluded. *)
val points_between : string -> int -> int -> int

(** The text of an argument, or a [type] panic naming the function. *)
val text_arg : ctx -> string -> t -> string

(** [flag_arg ctx param a k]: the optional argument [k], true or false, false when it is absent or missing; else a [type]
    panic naming the parameter. *)
val flag_arg : ctx -> string -> t array -> int -> bool

(** A native: name, minimum and maximum argument count, code. [result]: it gives an Ok or an Err. *)
val nat :
  ?perm:perm -> ?params:string array -> ?ret:(ty array -> ty) -> ?result:bool -> string -> int -> int ->
  (ctx -> t array -> t) -> t
