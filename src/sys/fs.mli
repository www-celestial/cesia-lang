(** Files and the environment. Regular files block the whole program for their duration: [epoll] doesn't apply to them. *)
open Cesia
open Types

(** An [Err] of this kind, with this message. *)
val failure : world -> string -> string -> t

(** The [Err] of a failed operation, with kind ["io"]. *)
val io_error : world -> string -> t

(** The reason in a [Unix] error, for a message. *)
val reason : Unix.error -> string

(** The [Err] of an operation that failed on a target: a verb, the target and the [Unix] error. *)
val failed : ctx -> string -> string -> Unix.error -> t

(** Does this error mean that the operation can be tried again? *)
val retry : Unix.error -> bool

(** The functions of the [sys] module that deal with files and the environment. *)
val natives : (string * t) list
