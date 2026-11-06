(** [cesia test]: the doc comment examples and the isFoo functions. *)
open Types

(** Runs the examples and the tests of a file or a folder, and returns the exit code. [seed]: of the cases of test.ForAll;
    [cases]: how many by default; [only]: the one test to run, by name. *)
val run : world -> path:string -> seed:int -> cases:int -> only:string option -> int

(** Set by the binary: removes a folder, never following a link. *)
val remove : (string -> unit) ref

(** Set by the binary: closes every socket and forgets every waiting fiber, at the end of each test. *)
val reset : (unit -> unit) ref

(** Stops the test running when it is past its deadline: the binary calls it while the program waits. *)
val tick : unit -> unit
