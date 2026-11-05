(** The IR as MIR text, and the backend that makes machine code of it. [src/sys] sets the backend; [src/lib] stays in
    OCaml alone. *)
open Types

(** What [src/sys] gives: [load text names] makes machine code of a module of MIR text and gives the address of each
    function named, or raises [Failure]; [call f ints floats values io] runs one, through the single entry of the JIT,
    and gives its status. [ints] and [io] are int arrays and [floats] a float array, as the stacks of a [ctx]. *)
type backend = {
  load : string -> string array -> nativeint array;
  call : nativeint -> int array -> floatarray -> t array -> int array -> int;
}

(** The backend, or [None] where the binary has no JIT. *)
val backend : backend option ref
