(** Debugging: hooks, reading frames, native module [debug]. *)
open Types

(** The hook, before each statement of a program run with --debugger. *)
val hook : ctx -> int -> unit

(** The hooks compiled: 0 without --debugger. *)
val hooks_compiled : world -> int

(** The contents of module [debug]. *)
val natives : (string * t) list
