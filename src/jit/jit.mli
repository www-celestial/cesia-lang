(** The JIT's machine code, by MIR. Nothing runs before the first [load]. *)

(** [load text names level]: machine code of a module of MIR text, made by MIR at that level (1, or 2: slower to make,
    faster to run) in a context of its own: the context first, then the address of each function named. Any domain may
    load; MIR works without the domain's lock. Raises [Failure] with MIR's message; after an error of MIR, every load
    fails. *)
val load : string -> string array -> int -> nativeint array

(** Frees a context that [load] gave, its machine code with it: only once nothing can run that code. *)
val free : nativeint -> unit

(** The contexts loaded and not freed yet: the tests check that units that die leave none behind. *)
val live : unit -> int

(** Runs a function through the single entry: [call f ints floats values io], its status. *)
val call : nativeint -> int array -> floatarray -> Cesia.Types.t array -> int array -> int
