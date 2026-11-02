(** The documentation of the language, read from the sources when it is asked for, so that it costs nothing at start. A
    comment placed just above a definition documents it. Natives have no source: [std/natives.k] holds their comments, each
    after a line [--- signature]. *)
open Types

(** The lines of a source, with its comment blocks read: a [(** ... *)] at the start of a line becomes [--] lines, and another
    block empty lines. They keep their numbers. *)
val lines : string -> string list

(** A comment line: the text after [--]. *)
val comment_text : string -> string option

(** A top-level definition: [defn], [struct], [name(...) = ...], or the short form of a method. *)
val is_definition : string -> bool

(** The signature in a line [--- signature] of comments for a native. *)
val native_header : string -> string option

(** [Doc] and [DocNames]. *)
val natives : (string * t) list

(** [kepler doc]: the modules, the names of a module, or the documentation of a name. Gives the exit code. *)
val command : world -> string list -> int
