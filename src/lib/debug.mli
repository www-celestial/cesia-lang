(** Debugging: hooks, reading frames, native module [debug]. *)
open Types

(** The hook, before each statement of a program run with --debugger. *)
val hook : ctx -> int -> unit

(** Is there a breakpoint at this line of this file (an index of [world.files])? Native code runs no hook, so such a line
    stays with the interpreter. *)
val armed : world -> int -> int -> bool

(** With a debugger: a panic stops the program where it happens, before it leaves. *)
val on_error : ctx -> string -> unit

(** [frame ctx base site]: a frame of a stop, as the debugger sees it: Function, File, Line and Vars. *)
val frame : ctx -> int -> int -> t

(** A row of values. *)
val row : t list -> t

(** The hooks compiled: 0 without --debugger. *)
val hooks_compiled : world -> int

(** The contents of module [debug]. *)
val natives : (string * t) list
