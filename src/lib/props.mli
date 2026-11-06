(** The cases of test.ForAll: each case is the tape of draws its generator made, which replays it and shrinks it. *)
open Types

(** What a failed ForAll leaves to the runner: the case that failed of how many (0 for a saved one), the draws it took and
    after shrinking, the smallest value, its panic, and the size it was made at. *)
type failure = { case : int; cases : int; from : int; until : int; value : t; panic : string option; size : int }

(** The state of the run: [active] under cesia test; the [seed] of the run; the default number of [cases]; the [root] of
    the project, where .cesia/failures/ keeps the failures found; the [file] (from the root) and the [test] running;
    whether a property [ran]; the [failed] ForAll of the test; [on_case] runs before each property; [dir] the run's folder,
    which holds the [temp] folder of each test, [count] the tests so far; the [deadline] of the test running, by [clock],
    [timeout] seconds after it started. The other fields are the tape of the case. *)
type state = {
  mutable active : bool;
  mutable seed : int;
  mutable cases : int;
  mutable root : string;
  mutable file : string;
  mutable test : string;
  mutable rank : int;
  mutable rng : int64;
  mutable tape : int array option;
  mutable pos : int;
  drawn : int Dynarray.t;
  mutable size : int;
  mutable ran : bool;
  mutable failed : failure option;
  mutable on_case : unit -> unit;
  mutable dir : string;
  mutable temp : string option;
  mutable count : int;
  mutable deadline : float;
  mutable timeout : float;
  mutable clock : unit -> float;
}

val st : state

(** A test starts: its ForAlls count from 1 again, none failed, it has no Temp folder yet, and its deadline starts. *)
val start_test : file:string -> test:string -> unit

(** The natives of std/test and std/gen, by package. *)
val natives : (string * (string * t) list) list
