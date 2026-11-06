(** [cesia test]: the doc comment examples and the isFoo functions. *)
open Types

(** Runs the examples and the tests of a file or a folder, and returns the exit code. [seed]: of the cases of test.ForAll;
    [cases]: how many by default; [only]: the one test to run, by name; [worker]: [path] is one unit of a larger run,
    whose tests are named as they start, and whose counts end its output. *)
val run : world -> path:string -> seed:int -> cases:int -> only:string option -> worker:bool -> int

(** What cesia test runs under a path, each in a worker of its own when there are several: the files that stand alone,
    and the folders of packages, with something to run. *)
val unit_paths : string -> string list

(** Set by the binary: removes a folder, never following a link. *)
val remove : (string -> unit) ref

(** Set by the binary: closes every socket and forgets every waiting fiber, at the end of each test. *)
val reset : (unit -> unit) ref

(** Stops the test running when it is past its deadline: the binary calls it while the program waits. *)
val tick : unit -> unit
