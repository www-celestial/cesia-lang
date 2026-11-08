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

(** Reloads these files, trying again what failed as long as something else loads: a package may need one that comes
    later. Gives what still fails, with its error. *)
val reload_all : world -> string list -> (string * string) list

(** The last module loaded from this path, or -1. *)
val module_of : world -> string -> int

(** The source last loaded from this path. *)
val source_of : world -> string -> string option

(** The files to watch for this program. *)
val watched : world -> string list

(** An error in the one form that Cesia shows: [Messages.at] its place and its text, then the line of [source] with a ^
    under the column, the hint, and the lines of [trace]. Ends with a line end. *)
val format_error :
  source:string option -> path:string -> pos:Pos.t -> text:string -> hint:string option -> trace:string list -> string

(** A Cesia error as the program shows it: its place, its line of code, its hint and the calls that led there, from the
    frames of [ctx] as they were when it was raised, down to the frame of base [above]; [None] for another exception. *)
val error_report : ?above:int -> ctx -> exn -> string option

(** The text of a Cesia error, or [None] for another exception. *)
val message_of_error : exn -> string option

(** Calls a Cesia function from a native that goes on after an error of the call: [Error] of the error, a Cesia error as
    [message_of_error] tells or the [Value.Quit] of sys.Exit, with the frame base and the site put back as a return
    leaves them. *)
val call_caught : ctx -> t -> t array -> (t, exn) result

(** [run_tool w name args] runs the tool [src/tools/NAME.ce] that the binary holds, with these arguments: its [Main()] gives
    [Ok], or an [Err] whose text goes to the errors, and then the code is 1. A tool sees no project's [std/]. *)
val run_tool : world -> string -> string list -> int
