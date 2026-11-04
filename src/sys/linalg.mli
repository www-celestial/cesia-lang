(** BLAS and LAPACK, when the machine has them: loaded at the first large computation, so that a program that doesn't need
    them pays nothing. [CESIA_BLAS] names a library, or [none] to go without one. *)
open Cesia
open Types

(** Sends the [Matmul] of large arrays to BLAS. *)
val install : unit -> unit

(** The [lapack] module. Each function gives [missing] when it can't help, and the caller then does the work itself. *)
val natives : (string * t) list
