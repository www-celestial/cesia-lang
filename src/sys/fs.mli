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

(** The paths under a folder, depth first, the names of each folder sorted, the folders left out: a link is listed, never
    followed, so that no walk loops. [skip dir name] leaves out a name and all it holds. Raises [Unix.Unix_error] for a
    folder that can't be listed, with its path. *)
val paths : ?skip:(string -> string -> bool) -> string -> string list

(** Removes a folder and all it holds, never following a link: a link goes, what it points to stays. *)
val remove_tree : string -> unit

(** The functions of the [sys] module that deal with files and the environment. *)
val natives : (string * t) list
