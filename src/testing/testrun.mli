(** [cesia test]: the doc comment examples and the isFoo functions. *)
open Types

(** Runs the examples and the tests of a run, as [config] says, and returns the exit code. Its numbers come from std/random's
    seed, which the binary sets. *)
val run : world -> Testing.config -> int

(** What cesia test runs under a path, each in a worker of its own when there are several: the files that stand alone,
    and the folders of packages, with something to run. *)
val unit_paths : string -> string list

(** Set by the binary: closes every socket and forgets every waiting fiber, at the end of each test. *)
val reset : (unit -> unit) ref

(** Stops the test running when it is past its deadline: the binary calls it while the program waits. *)
val tick : unit -> unit
