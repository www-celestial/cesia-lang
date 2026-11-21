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

(** The code point of the character at a byte, and how many bytes it holds: U+FFFD for one that is no UTF-8. A character
    is a byte that doesn't continue one, 10xxxxxx, and those that do after it; those at the start of a text are one. *)
val char_at : string -> int -> int * int

(** Where a text stops being UTF-8, as RFC 3629 defines it: its first byte that isn't, or its length. *)
val utf8_end : string -> int

(** Is the text UTF-8 all through? *)
val is_utf8 : string -> bool

(** A size given to [name]: an integer, or a float with no fraction, from 0; else a [type] panic naming [name]. *)
val dim : ctx -> string -> t -> int

(** The text of an argument, or a [type] panic naming the function. *)
val text_arg : ctx -> string -> t -> string

(** [flag_arg ctx param a k]: the optional argument [k], true or false, false when it is absent or missing; else a [type]
    panic naming the parameter. *)
val flag_arg : ctx -> string -> t array -> int -> bool

(** The type of the result of a native that says nothing of it, any value: never a number, as [Infer] knows. *)
val any : ty array -> ty

(** A native: name, minimum and maximum argument count, code. [ret]: the type of its result, by those of its arguments,
    [any] without it. [result]: it gives an Ok or an Err. *)
val nat :
  ?perm:perm -> ?params:string array -> ?ret:(ty array -> ty) -> ?result:bool -> string -> int -> int ->
  (ctx -> t array -> t) -> t
