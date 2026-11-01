(** Files and the environment. Regular files block the whole program for their duration: [epoll] doesn't apply to them. *)
open Kepler
open Types

(** An [Err] of this kind, with this message. *)
val failure : world -> string -> string -> t

(** The [Err] of a failed operation, with kind ["io"]. *)
val io_error : world -> string -> t

(** The reason in a [Unix] error, for a message. *)
val reason : Unix.error -> string

(** The functions of the [sys] module that deal with files and the environment. *)
val natives : (string * t) list
