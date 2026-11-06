(** Running code in a running program, the one engine of the prompt of [cesia run --repl] and of a debugger: at the file
    level of the main file's package, or in a frame of a stop. Its natives are part of std/debug; the plugin cesia_debug.cmxs holds it. *)
open Types

(** [debug.Eval], [debug.Reload] and [debug.Complete]. *)
val natives : (string * t) list

(** Is the condition of a breakpoint true at a site, with the variables there? An error says yes, to be seen. *)
val test : ctx -> int -> string -> bool
