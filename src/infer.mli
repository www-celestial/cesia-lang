(** Inference: the types of a version's variables and nodes, and its return type. *)
open Types

val join : ty -> ty -> ty

(** The version for this signature: at most 8 per function, then the generic version. *)
val version_for : world -> proto -> ty array -> version

val generic_version : proto -> version
val make_version : proto -> ty array -> version

(** Arranges the arguments by parameter. *)
val bind_args : Ast.func -> Ast.arg array -> (Ast.expr option array, Messages.t) result

(** Fills in [tv], [tn], [ret], [map] and [frame]. *)
val run : world -> version -> unit
