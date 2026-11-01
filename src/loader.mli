(** Loading files and printing errors. *)
open Types

(** Initializes the world, runs a file and returns the exit code. *)
val run_file : ?strict:bool -> world -> string -> string list -> int

(** Runs a file in an already initialized world. With [strict], an OCaml stack overflow or a memory refusal from the
    system stay exceptions: the fuzzer wants them, a normal program doesn't. *)
val run : ?strict:bool -> world -> string -> string list -> int

(** Runs a function, prints any Kepler error and returns the exit code. *)
val guarded : ?strict:bool -> world -> (ctx -> int) -> int

(** Creates the prelude module. *)
val init : world -> unit

(** A name of module [m], if it exists. *)
val in_module : world -> int -> string -> Ast.binding option

(** A name of the prelude. *)
val lookup : world -> string -> Ast.binding option

(** Loads a source as a new module, without running it. *)
val prepare :
  ?hooks:bool -> ctx -> path:string -> src:string -> lookup:(string -> Ast.binding option) ->
  int * int * Ast.func * Ast.layout

val run_prepared : ctx -> int * int * Ast.func * Ast.layout -> unit

(** Replaces the functions and structs of a module without rerunning its statements. Everything is parsed first: an
    error returns its text, and the old code stays in place. *)
val reload : world -> string -> (unit, string) result

(** The files to watch for this program. *)
val watched : world -> string list

(** The text of a Kepler error, or [None] for another exception. *)
val message_of_error : exn -> string option
