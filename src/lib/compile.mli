(** The compiler: from the tree to closures. *)
open Types

val new_proto : file:int -> m:int -> Ast.func -> proto

(** The most functions that a call through a value remembers in [version.seen]: past them it remembers one more, and no
    other, a call that reaches too many for the JIT to bet on. *)
val seen_most : int

(** The keys of the maps that a literal of these names makes, the same for every such literal. *)
val map_keys : string array -> keys

(** Gives the shape of a struct, declared in module [m], the types of its fields, which a write checks. *)
val set_checks : world -> int -> Ast.func -> unit

(** Does a version check a parameter or its result as it runs: a declared type that its version doesn't meet already, as
    a parameter Int in a version for a Float. Native code runs neither the checks of a call's start nor those of its way
    out, so the JIT leaves such a version to the interpreter. *)
val checks : version -> bool

(** Compiles and runs the file level of a module, at [ctx.b]: gives the value of its last statement. *)
val run_main : ctx -> file:int -> m:int -> Ast.func -> t

(** Calls a value, the called frame starting at [ctx.b + base]. *)
val call_value : ctx -> base:int -> t -> t array -> t

(** Calls a value from a native, above the frame of its call site, and leaves [ctx.site] at that site. *)
val call_back : ctx -> t -> t array -> t

(** Gives a function a new definition. *)
val replace : proto -> file:int -> Ast.func -> unit

(** After a reload: every function recompiles on its next call, and already compiled code calling an old version
    reaches the new code. *)
val retire_all : world -> unit
