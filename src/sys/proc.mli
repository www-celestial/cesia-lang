(** Running a command, without blocking the other fibers. *)
open Cesia
open Types

(** A duration given to [name], in seconds: a number of 0 or more. *)
val seconds : ctx -> string -> t -> float

(** The function [sys.Run]. *)
val natives : Poll.t -> (string * t) list
