(** The JIT's machine code, by MIR. Nothing runs before the first [load]. *)

(** Makes machine code of a module of MIR text; the address of each function named. Raises [Failure] with MIR's message;
    after an error of MIR, every load fails. *)
val load : string -> string array -> nativeint array

(** Runs a function through the single entry: [call f ints floats values io], its status. *)
val call : nativeint -> int array -> floatarray -> Cesia.Types.t array -> int array -> int

(** Sets the backend of [Cesia.Mirtext]. *)
val install : unit -> unit
