(** Running code in a running program, the one engine of the prompt of [cesia run --repl] and of a debugger: at the file
    level of the main file's package, or in a frame of a stop. Its natives are part of std/debug. *)
open Types

(** [debug.Eval], [debug.Reload] and [debug.Complete]. *)
val natives : (string * t) list

(** Makes the conditions of breakpoints run with this engine. *)
val install : world -> unit
