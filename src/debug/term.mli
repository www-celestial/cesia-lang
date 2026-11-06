(** debug.ReadLine: a line of the standard input, edited on a terminal, with the history of the lines read. *)
open Cesia
open Types

(** The native, which waits for the input as a fiber does for any. *)
val natives : Poll.t -> (string * Types.t) list
