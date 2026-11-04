(** Running a command, without blocking the other fibers. *)
open Cesia
open Types

(** The function [sys.Run]. *)
val natives : Poll.t -> (string * t) list
