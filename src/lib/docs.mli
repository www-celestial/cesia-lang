(** The documentation of the language, read from the sources when it is asked for, so that it costs nothing at start. A
    [(** *)] documents what it belongs to: the definition whose body it opens, or the one-line definition at the end of whose line
    or just above which it is; a field, a parameter or the result at the end of its line. Natives have no source:
    [std/natives.ce] holds a [(** *)] for each, whose first line is its signature. *)
open Types

(** The lines of a documentation that are examples, indented under its text, each with its line number. *)
val examples : string -> (int * string) list

(** [Doc] and [DocNames]. *)
val natives : (string * t) list

(** [cesia doc]: the modules, the names of a module, or the documentation of a name. Gives the exit code. *)
val command : world -> string list -> int
