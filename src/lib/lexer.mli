(** The lexer. It emits every newline: the parser decides according to its mode. *)

type tok =
  | INT of int
  | FLOAT of float
  | TEXT of part list
  | NAME of string
  | IF | ELSE | END | FOR | IN | WHILE | BREAK | RETURN | DEFN | MATCH | STRUCT | INTERFACE
  | AND | OR | NOT | THEN | USE | TRUE | FALSE | MISSING
  | PLUS | MINUS | STAR | SLASH | CARET
  | ASSIGN | EQEQ | NE | LT | LE | GT | GE
  | PLUSEQ | MINUSEQ | STAREQ | SLASHEQ
  | ARROW | COLON | SEMI | COMMA | DOT | DOTDOT | QUESTION | BANG
  | LP | RP | LB | RB | LC | RC
  | NL
  | EOF

and token = { t : tok; pos : Pos.t; sp : bool  (** a space precedes the token *) }

and part = Plain of string | Code of token array

val tokens : file:string -> string -> token array

(** The reserved words, then those that mean something in some places only: [it], [as], [_] and [?]. *)
val words : string list

(** A capital first letter makes a name public. *)
val is_public : string -> bool

(** A name the code can write, so a key that prints without quotes: no keyword, no [_]. *)
val is_plain_name : string -> bool

(** A name from outside as a public name: [created_at] gives [CreatedAt], [name] [Name]. A text that is no identifier stays. *)
val public_name : string -> string

(** The name of a method inside the core. [Rect.Area] gives the struct, [false] and the method; [Rect:Square], which only the
    core writes, gives [true]; another name gives [None]. *)
val split_method : string -> (string * bool * string) option
