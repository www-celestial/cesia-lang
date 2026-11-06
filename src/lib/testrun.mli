(** [cesia test]: the doc comment examples and the isFoo functions. *)
open Types

(** Runs the examples and the tests of a file or a folder, and returns the exit code. [seed]: of the cases of test.ForAll;
    [cases]: how many by default; [only]: the one test to run, by name. *)
val run : world -> path:string -> seed:int -> cases:int -> only:string option -> int
