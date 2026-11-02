(** The native modules of [sys/], for [bin/main.ml] and the tests. *)
open Kepler
open Types

(** Adds [sys] and [net] to the world and makes it able to wait. [max_sleep] caps [sys.Sleep]: the fuzzer would hang on a
    huge duration otherwise. [tick] is a period and a function called at least that often while the program is blocked.
    [watching] is for [kepler run --watch], which must know of a stop signal even if a window hears of it: only then does
    [sys.TakeStops] do anything. The function returned says whether a stop signal arrived. *)
val register : ?max_sleep:float -> ?tick:float * (unit -> unit) -> ?watching:bool -> world -> unit -> bool

(** The RAM of the machine in bytes, or 0 if it can't be known. *)
val ram : unit -> int
