(** The hooks of cesia test, whose code is in the plugin cesia_testing.cmxs (src/testing/): the binary loads it for
    cesia test only, so that a program's start-up never pays for it. *)
open Types

(** A run of cesia test: the [path] to test, the [cases] of each property, the one test to run, by name; [worker]: [path]
    is one unit of a larger run; [update]: snapshots are written; [dir]: the run's folder, for the Temp folders; the
    [timeout] of a test in seconds, by [clock]; [remove] deletes a folder without following links. *)
type config = {
  path : string;
  cases : int;
  only : string option;
  worker : bool;
  update : bool;
  dir : string;
  timeout : float;
  clock : unit -> float;
  remove : string -> unit;
}

(** What the plugin gives: [run] a world and returns the exit code; the [units] of a path, one worker each; [tick] stops a
    test past its deadline while it waits; [reset] receives the function that closes the sockets and forgets the waiting
    fibers at the end of each test. *)
type runner = {
  run : world -> config -> int;
  units : string -> string list;
  tick : unit -> unit;
  reset : (unit -> unit) ref;
}

(** Set by the plugin when it loads. *)
val runner : runner option ref

(** isGrows: [is], then a capital: the name of a test. *)
val is_test : string -> bool
