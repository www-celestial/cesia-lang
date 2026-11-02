(** Resolution: scopes, captures, definite assignment, tail positions. *)

(** What a file defines for its package: the name inside the core, the name to show, where, and whether it is a function. *)
val definitions : Ast.func -> (string * string * Pos.t * bool) list

(** The files of a package, with their paths: two of them can't define one name. *)
val check_package : (string * Ast.func) list -> unit

(** Fills in the [binding]s of file [fn], for the module of index [m]. The names in [keep] keep their cell index: a
    reload moves nothing for already compiled code. [peers] are the files of its package: their structs and fields count as
    its own, and each name in [keep] lives in its cell. With [sees_private], a small field or method needs no declaration
    here: that is for the examples of a file. *)
val file :
  ?keep:string array -> ?peers:Ast.func list -> ?sees_private:bool -> file:string -> m:int ->
  lookup:(string -> Ast.binding option) ->
  spaces:(string * (string -> Ast.binding option)) list -> Ast.func -> Ast.layout

(** Applies a function to the direct subexpressions, without entering nested functions. *)
val children : (Ast.expr -> unit) -> Ast.expr -> unit

(** Says that parameter [k] must not be lent: the function can write it, reassign it or return it. *)
val keeps : Ast.func -> int -> bool
