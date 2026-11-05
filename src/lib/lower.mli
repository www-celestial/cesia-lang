(** From a version to the IR: phase 1 of the JIT takes integers, floats and float arrays, loops, conditions, calls
    between such versions and the natives with a meaning known in MIR or libm. *)
open Types

(** The functions of a unit: the version first, then each version it calls, all lowered; or [None] when anything is
    outside phase 1, and the version stays interpreted. Registers the sites of their errors and calls, on success only. *)
val unit : world -> version -> Ir.func array option
