(** Loading files and printing errors. *)
open Types

(** Initializes the world, runs a file and returns the exit code. *)
val run_file : ?strict:bool -> world -> string -> string list -> int

(** Runs a file in an already initialized world. With [strict], an OCaml stack overflow or a memory refusal from the
    system stay exceptions: the fuzzer wants them, a normal program doesn't. *)
val run : ?strict:bool -> world -> string -> string list -> int

(** Runs a function, prints any Cesia error and returns the exit code. *)
val guarded : ?strict:bool -> world -> (ctx -> int) -> int

(** Prepares the world: module 0 of what only the compiler names, and the natives of the packages of std/, which load at
    their first use. *)
val init : world -> unit

(** A name of module [m], if it exists. *)
val in_module : world -> int -> string -> Ast.binding option

(** A name of any file of the package of module [m]. *)
val in_package : world -> int -> string -> Ast.binding option

(** What every file sees without a use: only the names that the parser writes, as [#dict]. *)
val lookup : world -> string -> Ast.binding option

(** The package of std/ of a name written without its package, as io for Print: the table of the messages that say which
    use to write. *)
val home : world -> string -> string option

(** The module of the natives of the package of std/ that a file of std/ is part of, as src/std/list.ce, if it has them. *)
val std_natives : world -> string -> int option

(** Loads a source as a new module, without running it. With [host], the source sees the private fields and methods of
    that module; with [natives], the natives of its package of std/, as [std_natives] gives them; [rewrite] changes its tree
    before its names are resolved, as for the verdicts of a test. *)
val prepare :
  ?hooks:bool -> ?host:int -> ?natives:int -> ?rewrite:(Ast.func -> unit) -> ctx -> path:string -> src:string ->
  lookup:(string -> Ast.binding option) ->
  int * int * Ast.func * Ast.layout

val run_prepared : ctx -> int * int * Ast.func * Ast.layout -> unit

(** Loads a folder as a package and runs its statements, once, and gives its first module. *)
val folder : ctx -> string -> int

(** Replaces the functions and structs of a module without rerunning its statements. Everything is parsed first: an
    error returns its text, and the old code stays in place. *)
val reload : world -> string -> (unit, string) result

(** The files to watch for this program. *)
val watched : world -> string list

(** The text of a Cesia error, or [None] for another exception. *)
val message_of_error : exn -> string option

(** The libraries of this Cesia, as [use std/x] finds them without a copy: each name and its source. *)
val libraries : unit -> (string * string) list

(** [run_tool w name args] runs the tool [src/tools/NAME.ce] that the binary holds, with these arguments: its [Main()] gives
    [Ok], or an [Err] whose text goes to the errors, and then the code is 1. A tool sees no project's [std/]. *)
val run_tool : world -> string -> string list -> int
