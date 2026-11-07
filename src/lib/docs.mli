(** The documentation of the language, read from the sources when it is asked for, so that it costs nothing at start. A
    [(** *)] documents what it belongs to: the definition whose body it opens, or the one-line definition at the end of whose line
    or just above which it is; a field, a parameter or the result at the end of its line. Natives have no source:
    [std/natives.ce] holds a [(** *)] for each, whose first line is its signature. *)
open Types

(** The files of std/ that are the language, not libraries: the documentation of the natives and of the keywords. *)
val language : string list

(** The lines of a documentation that are examples, indented under its text, each with its line number: those of the
    [(** *)] at the top of the file first, then those of its names. *)
val examples : string -> (int * string) list

(** [cesia.DocEntry(name)]: [{Name, Module, Signature, Text, Parts, Examples, Builtin, File, Line}] of a name or a keyword, or
    missing. *)
val doc_entry : ctx -> t array -> t

(** [Doc] and [DocNames]. *)
val natives : (string * t) list

(** [cesia doc]: the modules, the names of a module, or the documentation of a name. Gives the exit code. [home] gives the
    package of std/ of a name written without it, as list for Map, which the message names. *)
val command : home:(string -> string option) -> world -> string list -> int
