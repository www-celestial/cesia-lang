(** From a version to the IR: integers, floats and float arrays, loops, conditions, calls between such versions and the
    natives with a meaning known in MIR or libm; in a region, also values of any type: maps and structs read behind guards
    on their keys or shape, made in reserved room, arrays of values. A failed guard bails: the run stops before the
    statement of the region's loop it is in, and the interpreter goes on from there. *)
open Types

(** The functions of a unit: the version first, then each version it calls, all lowered; or [None] when anything is
    outside phase 1, and the version stays interpreted. Registers the sites of their errors and calls, on success only. *)
val unit : world -> version -> Ir.func array option

(** A loop of a version alone, as the first function of a unit: its resume point at the loop's start, and for each loop it
    holds, itself included, the loop's node, the slots of its counter and bound or -1 for a [while], and its resume point
    after the step of an iteration. A [for] keeps its counter in its variable's slot when its body leaves it alone. *)
val region : ?ctx:ctx -> world -> version -> Ast.expr -> (Ir.func array * int * (int * int * int * int) array) option

(** Raised by [region] when a guess needs a value that the frame [ctx] doesn't hold yet, as before the loop's first step:
    the loop can be lowered again later. Values of any type, maps and structs, are lowered only in regions, from what
    [ctx] holds: the keys of a map or the shape of a struct read there, an Int or a Float in arithmetic. *)
exception Unseen
