(** The second tier: versions and loops that get hot run as native code, made by [Lower] and [Mirtext], with the same
    output, errors and limits as the interpreter. Nothing of it runs before something gets hot. Written types give no
    speed of their own: the types are those that inference proved. *)
open Types

(** Native code of a version or of a loop. *)
type code

(** The modes: [off] ([--no-jit], [CESIA_JIT=off]), [hot], the default, and [always] ([CESIA_JIT=always]), which compiles
    each candidate at its first call or run, for tests. [CESIA_JIT_SHOW=1] prints the MIR of each unit on stderr. *)
val off : int

val hot : int
val always : int
val mode : int ref

(** After [Compile] made a version's entries: counts its calls, then gives it native entries when it lowers. Does nothing
    for a version that can't be a candidate. *)
val watch : world -> version -> unit

(** The native state of one loop of a version: [Compile] keeps one with each loop it compiles, with the loop's expression. *)
type loop

val loop : Ast.expr -> loop

(** Can loops be native at all: a JIT in the binary, and not off. *)
val on : unit -> bool

(** The native code of this loop of the version, when it has some; in mode [always], compiles it at its first run. *)
val ready : ctx -> loop -> version -> code option

(** At a checkpoint inside the loop, given the loops around it, the nearest first: when hot, the native code of the
    outermost of them, the loop included, that lowers. The interpreter then raises [Handoff] with that code and the loop's
    node, and each loop around it, on its way out, puts its counter in its slot ([place]); the one whose code it is
    ([is_root]) enters native code [after] the step of that loop. *)
val hot : ctx -> loop -> version -> loop list -> code option

exception Handoff of code * int

val id : loop -> int

(** [place ctx code l n hi]: the counter [n] and bound [hi] of [l], a [for], in their slots. *)
val place : ctx -> code -> loop -> int -> int -> unit

val is_root : code -> loop -> bool
val after : code -> int -> int

(** [Ran]: the loop ran to its end natively, every variable back in its slot; [Fell]: nothing ran, the loop stays
    interpreted from now on; [Returned]: a [return] inside, with its value. *)
type ran = Ran | Fell | Returned of t

(** Runs the loop natively from [start code], its counter and bound put in their slots ([place]), or from
    [after code node]. *)
val enter : ctx -> loop -> code -> int -> ran

val start : code -> int
