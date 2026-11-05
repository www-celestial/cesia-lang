(** From a version to the IR: phase 1 of the JIT takes integers, floats and float arrays, loops, conditions, calls
    between such versions and the natives with a meaning known in MIR or libm. *)
open Types

(** The functions of a unit: the version first, then each version it calls, all lowered; or [None] when anything is
    outside phase 1, and the version stays interpreted. Registers the sites of their errors and calls, on success only. *)
val unit : world -> version -> Ir.func array option

(** A loop of a version alone, as the first function of a unit: its resume point at the loop's start, and for each loop it
    holds, itself included, the loop's node, the slots of its counter and bound or -1 for a [while], and its resume point
    after the step of an iteration. A [for] keeps its counter in its variable's slot when its body leaves it alone. *)
val region : world -> version -> Ast.expr -> (Ir.func array * int * (int * int * int * int) array) option
