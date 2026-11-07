(** The standard input, through one buffer: sys.ReadInput takes bytes of it, debug.ReadLine a line, which the line editor
    edits on a terminal. *)
open Cesia
open Types

(** What was read of the input and not yet taken. *)
type state

val create : Poll.t -> state

(** sys.ReadInput, which waits for the input as a fiber does for any. *)
val input : state -> (string * Types.t) list

(** debug.ReadLine. On a terminal, [editor] gives the line editor, a function of the prompt and of the next byte, or
    [None] to read lines as they come. *)
val natives :
  editor:(unit -> (string -> (unit -> char option) -> string option) option) -> state -> (string * Types.t) list
