(** Loops over [F] storage, with no boxed value. *)

type op = Add | Sub | Mul | Div

val both : op -> floatarray -> floatarray -> floatarray
val right : op -> floatarray -> float -> floatarray
val left : op -> float -> floatarray -> floatarray
val map1 : (float -> float) -> floatarray -> floatarray
val sum : floatarray -> float
val matmul : rows:int -> cols:int -> inner:int -> out:floatarray -> floatarray -> floatarray -> floatarray
val transpose : rows:int -> cols:int -> floatarray -> floatarray
