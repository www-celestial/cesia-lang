(** Loops over [F] storage, with no boxed value. *)

type op = Add | Sub | Mul | Div

val both : op -> floatarray -> floatarray -> floatarray
val right : op -> floatarray -> float -> floatarray
val left : op -> float -> floatarray -> floatarray
val map1 : (float -> float) -> floatarray -> floatarray
val sum : floatarray -> float
(** A faster [Matmul], from a library, for what it can take. It says whether it did the work. *)
val fast_matmul : (rows:int -> cols:int -> inner:int -> out:floatarray -> floatarray -> floatarray -> bool) ref

val matmul : rows:int -> cols:int -> inner:int -> out:floatarray -> floatarray -> floatarray -> floatarray
(** The positions from 0 to [n], stably sorted by a comparison of two positions. [parallel] says that the comparison can run
    on several cores: it touches nothing and can't panic. *)
val sort_positions : ?parallel:bool -> int -> (int -> int -> int) -> int array

val transpose : rows:int -> cols:int -> floatarray -> floatarray
