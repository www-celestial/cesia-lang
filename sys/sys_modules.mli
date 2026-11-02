(** The native modules of [sys/], for [bin/main.ml] and the tests. *)
open Kepler
open Types

(** Adds [sys] and [net] to the world and makes it able to wait. [max_sleep] caps [sys.sleep]: the fuzzer would hang on a
    huge duration otherwise. [tick] is a period and a function called at least that often while the program is blocked.
    The function returned says whether a stop signal arrived. *)
val register : ?max_sleep:float -> ?tick:float * (unit -> unit) -> world -> unit -> bool

(** The RAM of the machine in bytes, or 0 if it can't be known. *)
val ram : unit -> int
