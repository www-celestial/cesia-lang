(** Loops over [F] and [I] storage, with no boxed value. *)

type op = Add | Sub | Mul | Div

val both : op -> floatarray -> floatarray -> floatarray
val right : op -> floatarray -> float -> floatarray
val left : op -> float -> floatarray -> floatarray

(** [ints op (x, step) (y, step) n]: n cells of integers, or [None] if one overflows. A step of 0 reads one cell, a scalar. *)
val ints : op -> int array * int -> int array * int -> int -> int array option

val of_ints : int array -> floatarray

(** [right] and [left] on integers, each made a float on the way. *)
val right_ints : op -> int array -> float -> floatarray
val left_ints : op -> float -> int array -> floatarray

(** Comparisons into a mask of [True] and [False]; [x > y] is [y < x]. *)
type test = Lt | Le | Eq | Ne

val mask_ints : test -> int array * int -> int array * int -> Types.t array -> unit
val mask_floats : test -> floatarray * int -> floatarray * int -> Types.t array -> unit
val map1 : (float -> float) -> floatarray -> floatarray
val sum : floatarray -> float
(** A faster [Matmul], from a library, for what it can take. It says whether it did the work. *)
val fast_matmul : (rows:int -> cols:int -> inner:int -> out:floatarray -> floatarray -> floatarray -> bool) ref

val matmul : rows:int -> cols:int -> inner:int -> out:floatarray -> floatarray -> floatarray -> floatarray
(** The positions from 0 to [n], stably sorted by a comparison of two positions. [parallel] says that the comparison can run
    on several cores: it touches nothing and can't panic. *)
val sort_positions : ?parallel:bool -> int -> (int -> int -> int) -> int array

val transpose : rows:int -> cols:int -> floatarray -> floatarray
