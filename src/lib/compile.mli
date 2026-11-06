(** The compiler: from the tree to closures. *)
open Types

val new_proto : file:int -> m:int -> Ast.func -> proto

(** The keys of the maps that a literal of these names makes, the same for every such literal. *)
val map_keys : string array -> keys

(** Gives the shape of a struct, declared in module [m], the types of its fields, which a write checks. *)
val set_checks : world -> int -> Ast.func -> unit

(** Compiles and runs the file level of a module, at [ctx.b]: gives the value of its last statement. *)
val run_main : ctx -> file:int -> m:int -> Ast.func -> t

(** Calls a value, the called frame starting at [ctx.b + base]. *)
val call_value : ctx -> base:int -> t -> t array -> t

(** Calls a value from a native, above the frame of its call site. *)
val call_back : ctx -> t -> t array -> t

(** Gives a function a new definition. *)
val replace : proto -> file:int -> Ast.func -> unit

(** After a reload: every function recompiles on its next call, and already compiled code calling an old version
    reaches the new code. *)
val retire_all : world -> unit
