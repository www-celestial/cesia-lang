(** The second tier, as the interpreter sees it: versions and loops that get hot run as native code, with the same output,
    errors and limits as the interpreter. This module only counts what gets hot; the JIT itself, src/jit, is a plugin that
    the binary loads at the first hot unit through [loader], and that fills [jit]: its code costs nothing at start-up. When
    it is missing or refused, everything stays interpreted. Written types give no speed of their own: the types are those
    that inference proved. *)
open Types

(** Native code of a version or of a loop: the JIT adds its constructor. *)
type code = ..

(** The modes: [off] ([--no-jit], [CESIA_JIT=off]), [hot], the default, and [always] ([CESIA_JIT=always]), which compiles
    each candidate at its first call or run, for tests. [CESIA_JIT_SHOW=1] prints the MIR of each unit on stderr, and why
    the JIT didn't load. *)
val off : int

val hot : int
val always : int
val mode : int ref

(** Set under [--watch]: a version with loops then runs them as regions, never as a whole, so that a reload hands each one
    over to the interpreter after a step. A loop-free version (recursion) still runs natively as a whole: after a reload,
    the call running natively ends with the old code, and the next call is the interpreter's. *)
val watching : bool ref

(** A version runs natively after this many calls; a loop after this many checkpoints inside it. *)
val calls_before : int

val checkpoints_before : int

(** The native state of one loop of a version: [Compile] keeps one with each loop it compiles, with the loop's expression;
    the JIT fills [code], made at [reloads], or sets [failed]; [tries] counts the times its code was dropped, or could not
    be made yet. *)
type loop = {
  mutable seen : int;
  mutable code : code option;
  mutable reloads : int;
  mutable failed : bool;
  mutable tries : int;
  expr : Ast.expr;
}

val loop : Ast.expr -> loop

exception Handoff of code * int

(** [Ran]: the loop ran to its end natively, every variable back in its slot; [Fell]: nothing ran, this run is the
    interpreter's; [Returned]: a [return] inside, with its value; [Reloaded]: a reload came, native code stopped after a
    step of this loop, every variable in its slot, and the interpreter goes on with the new code ([counter] tells a [for]
    where); [Bailed k]: a guard failed before statement [k] of the loop's body, or before a [while]'s test at -1, before
    anything of it showed: every variable in its slot, the interpreter goes on from there. *)
type ran = Ran | Fell | Returned of t | Reloaded | Bailed of int

(** What the JIT does: [promote] gives a hot version its native entries when it lowers, [compile] makes a loop's code,
    [pick] chooses the region at a hot checkpoint; the others are below. *)
type jit = {
  promote : world -> version -> unit;
  compile : ctx -> loop -> version -> unit;
  pick : ctx -> loop -> version -> loop list -> code option;
  place : ctx -> code -> loop -> int -> int -> unit;
  after : code -> int -> int;
  enter : ctx -> loop -> code -> int -> ran;
  start : code -> int;
  counter : ctx -> code -> loop -> int;
}

val jit : jit option ref

(** Loads the JIT, which sets [jit]: called once, at the first hot unit. The binary sets it, and [available]; else
    nothing loads. *)
val loader : (unit -> unit) ref

val available : bool ref

(** Can loops be native at all: a JIT to load, and not off. *)
val on : unit -> bool

(** After [Compile] made a version's entries: counts its calls, then gives it native entries when it lowers. Does nothing
    for a version that can't be a candidate. *)
val watch : world -> version -> unit

(** The native code of this loop of the version, when it has some; in mode [always], compiles it at its first run. *)
val ready : ctx -> loop -> version -> code option

(** At a checkpoint inside the loop, given the loops around it, the nearest first: when hot, the native code of the
    outermost of them, the loop included, that lowers. The interpreter then raises [Handoff] with that code and the loop's
    node, and each loop around it, on its way out, puts its counter in its slot ([place]); the one whose code it is
    ([is_root]) enters native code [after] the step of that loop. *)
val hot : ctx -> loop -> version -> loop list -> code option

val id : loop -> int

(** [place ctx code l n hi]: the counter [n] and bound [hi] of [l], a [for], in their slots. *)
val place : ctx -> code -> loop -> int -> int -> unit

val is_root : code -> loop -> bool
val after : code -> int -> int

(** Runs the loop natively from [start code], its counter and bound put in their slots ([place]), or from
    [after code node]. *)
val enter : ctx -> loop -> code -> int -> ran

val start : code -> int

(** The counter of a [for] that native code ran, from its slot. *)
val counter : ctx -> code -> loop -> int
