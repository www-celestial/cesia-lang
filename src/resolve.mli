(** Resolution: scopes, captures, definite assignment, tail positions. *)

(** Fills in the [binding]s of file [fn], for the module of index [m]. The names in [keep] keep their cell index: a
    reload moves nothing for already compiled code. *)
val file :
  ?keep:string array -> file:string -> m:int -> lookup:(string -> Ast.binding option) ->
  spaces:(string * (string -> Ast.binding option)) list -> Ast.func -> Ast.layout

(** Applies a function to the direct subexpressions, without entering nested functions. *)
val children : (Ast.expr -> unit) -> Ast.expr -> unit

(** Says that parameter [k] must not be lent: the function can write it, reassign it or return it. *)
val keeps : Ast.func -> int -> bool
