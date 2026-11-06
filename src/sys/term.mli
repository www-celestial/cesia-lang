(** debug.ReadLine: a line of the standard input, which the line editor edits on a terminal. *)
open Cesia
open Types

(** The native, which waits for the input as a fiber does for any. On a terminal, [editor] gives the line editor, a
    function of the prompt and of the next byte, or [None] to read lines as they come. *)
val natives :
  editor:(unit -> (string -> (unit -> char option) -> string option) option) -> Poll.t -> (string * Types.t) list
