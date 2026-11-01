(** A position in a file, held in an integer. The column counts code points. *)
type t = int

val make : int -> int -> t
val line : t -> int
val col : t -> int

(** Error raised at load time by the lexer, parser and resolver, which have no [world]. *)
exception Load_error of { file : string; pos : t; kind : string; text : string; hint : string option }
