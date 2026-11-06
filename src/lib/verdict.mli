(** Failures that explain themselves: the verdict of each test of a file, rewritten so that each of its parts notes its value
    through [#note(k, e)], which keeps the value of [e] for note [k] and gives it back; then what a failed test shows. *)

(** A part of a verdict: [Site n] what a test gives (its last expression or a return) of [n] parts joined by [and], [not] or
    [list.All], [Any n] of [n] parts joined by [or], [Part i] the part [i] of its site, [Shown] a value inside a part,
    [Hidden] a literal side of a comparison, [Question line] what a [?] receives. *)
type kind = Site of int | Any of int | Part of int | Shown | Hidden | Question of int

(** The sides of a comparison: [==] or [value.Equal], or [math.Near] with its [rel] and [abs], -1 when absent. *)
type sides = Equal of int * int | Near of int * int * int * int

(** A note: its test; the parameter of the property of [test.ForAll] it is in, or [""]; the note it belongs to, or -1; the
    code as written. *)
type note = { test : string; prop : string; owner : int; text : string; kind : kind; mutable sides : sides option }

(** isGrows: [is], then a capital. *)
val is_test : string -> bool

(** The code of an expression, as written. *)
val show : Ast.expr -> string

(** Rewrites the tests of a file, each [isX] with no parameter, in place: its nodes keep their ids, the new ones come after.
    Gives the notes, by number. *)
val rewrite : Ast.func -> note array

(** What a failed test shows: the end of its first line and the lines under it, from the value of each note in the last run
    of the test, and when, or [None] when no verdict ran. [prop]: the verdict of a property of [test.ForAll]. *)
val explain :
  Types.ctx -> note array -> (Types.t * int) option array -> test:string -> prop:bool -> Types.t -> (string * string list) option
