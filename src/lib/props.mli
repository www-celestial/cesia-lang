(** The cases of test.ForAll: each case is the tape of draws its generator made, which replays it and shrinks it. *)
open Types

(** What a failed ForAll leaves to the runner: the case that failed of how many (0 for a saved one), the draws it took and
    after shrinking, the smallest value, its panic, and the size it was made at. *)
type failure = { case : int; cases : int; from : int; until : int; value : t; panic : string option; size : int }

(** The state of the run: [active] under cesia test; the default number of [cases]; the [root] of
    the project, where .cesia/failures/ keeps the failures found; the [file] (from the root) and the [test] running;
    whether a property [ran]; the [failed] ForAll of the test; [on_case] runs before each property; [dir] the run's folder,
    which holds the [temp] folder of each test, [count] the tests so far; the [deadline] of the test running, by [clock],
    [timeout] seconds after it started; the [path] of its file; whether snapshots [update]; the [snaps] of the test so
    far, the [store] of its file, those [taken] in the run, and what the [snap_failure] of the test shows. The other fields
    are the tape of the case. *)
type state = {
  mutable active : bool;
  mutable cases : int;
  mutable root : string;
  mutable file : string;
  mutable test : string;
  mutable rank : int;
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
  mutable path : string;
  mutable update : bool;
  mutable snaps : int;
  mutable store : (string * (string * int, string) Hashtbl.t) option;
  taken : (string * int, string) Hashtbl.t;
  mutable snap_failure : string list;
}

val st : state

(** A test starts: its ForAlls count from 1 again, none failed, it has no Temp folder yet, its deadline starts, and its
    numbers start from the seed of the run and its name. *)
val start_test : path:string -> file:string -> test:string -> unit

(** With --update, writes the snapshots of a file: those of the tests that [ran] replace theirs, and those of the others of
    [tests] stay; then forgets the snapshots taken. *)
val write_snaps : string -> ran:string list -> tests:string list -> unit

(** The natives of std/test and std/gen, by package. *)
val natives : (string * (string * t) list) list
