(** The lexer. It emits every newline: the parser decides according to its mode. *)

type tok =
  | INT of int
  | FLOAT of float
  | TEXT of part list
  | NAME of string
  | IF | ELSE | END | FOR | IN | WHILE | BREAK | RETURN | DEFN | MATCH | STRUCT
  | AND | OR | NOT | THEN | USE | TRUE | FALSE | MISSING
  | PLUS | MINUS | STAR | SLASH | CARET
  | ASSIGN | EQEQ | NE | LT | LE | GT | GE
  | PLUSEQ | MINUSEQ | STAREQ | SLASHEQ
  | ARROW | COLON | SEMI | COMMA | DOT | QUESTION
  | LP | RP | LB | RB | LC | RC
  | NL
  | EOF

and token = { t : tok; pos : Pos.t; sp : bool  (** a space precedes the token *) }

and part = Plain of string | Code of token array

val tokens : file:string -> string -> token array
