(** The native modules of [sys/], for [bin/main.ml] and the tests. *)
open Cesia
open Types

(** Adds [sys] and [net] to the world and makes it able to wait. [max_sleep] caps [sys.Sleep] and every timer, as the
    timeout of [Receive]: the fuzzer would hang on a huge duration otherwise. [tick] is a period and a function called at least that often while the program is blocked.
    [watching] is for [cesia run --watch], which must know of a stop signal even if a window hears of it: only then does
    [sys.TakeStops] do anything. [reset] receives a function that closes every socket and forgets every waiting fiber, for
    the end of a test. The function returned says whether a stop signal arrived. *)
val register :
  ?max_sleep:float -> ?tick:float * (unit -> unit) -> ?watching:bool -> ?reset:(unit -> unit) ref -> world -> unit -> bool

(** The RAM of the machine in bytes, or 0 if it can't be known. *)
val ram : unit -> int

(** The code of sqlite3's natives by name, which its plugin cesia_sqlite.cmxs gives when it loads; empty before. *)
val sqlite3 : (string * (ctx -> t array -> t)) list ref

(** Loads that plugin, at the first call of sqlite3: [Error] says why it didn't. [bin/main.ml] sets it. *)
val sqlite_loader : (unit -> (unit, string) result) ref

(** The code of std/debug's engine, which its plugin cesia_debug.cmxs gives when it loads: its natives, the test of a
    condition of a breakpoint, and the line editor of ReadLine on a terminal. *)
val debugger :
  ((string * t) list * (ctx -> int -> string -> (bool, string) result) * (string -> (unit -> char option) -> string option))
  option ref

(** Loads that plugin, at the first call of one of its natives: [Error] says why it didn't. [bin/main.ml] sets it. *)
val debug_loader : (unit -> (unit, string) result) ref
