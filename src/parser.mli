(** The parser, shared by the interpreter and all tools. *)

(** The whole file, as a function with no parameters. *)
val program : ?hooks:bool -> file:string -> nesting:int -> Lexer.token array -> Ast.func
