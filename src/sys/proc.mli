(** Running a command, without blocking the other fibers. *)
open Cesia
open Types

(** A duration given to [name], in seconds: a number of 0 or more. *)
val seconds : ctx -> string -> t -> float

(** Passes a stop signal on to the processes this program started and hasn't waited for: TERM to each, INT and HUP to
    those that lead a process group of their own, which a terminal doesn't reach. *)
val pass_on : int -> unit

(** Called before each process starts: Net makes the stop signals reach it. *)
val on_start : (unit -> unit) ref

(** The end of a test: stops and waits for each process started and not waited for. *)
val reset : unit -> unit

(** The function [sys.Run]. *)
val natives : Poll.t -> (string * t) list
