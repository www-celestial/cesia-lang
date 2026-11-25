(** Loops over [F] and [I] storage, with no boxed value. *)

(** [Pow] is OCaml's [**], the C library's pow, as [Arith.pow] on one cell: the same bits; [Hypot], the C library's hypot. *)
type op = Add | Sub | Mul | Div | Pow | Hypot

val both : op -> floatarray -> floatarray -> floatarray
val right : op -> floatarray -> float -> floatarray
val left : op -> float -> floatarray -> floatarray

(** [ints op (x, step) (y, step) n]: n cells of integers, or [None] if one overflows or [op] is [Div] or [Pow]. A step of
    0 reads one cell, a scalar. *)
val ints : op -> int array * int -> int array * int -> int -> int array option

val of_ints : int array -> floatarray

(** [right] and [left] on integers, each made a float on the way. *)
val right_ints : op -> int array -> float -> floatarray
val left_ints : op -> float -> int array -> floatarray

(** Comparisons into a mask of [True] and [False]; [x > y] is [y < x]. *)
type test = Lt | Le | Eq | Ne

val mask_ints : test -> int array * int -> int array * int -> Types.t array -> unit
val mask_floats : test -> floatarray * int -> floatarray * int -> Types.t array -> unit
(** The functions of one float that [map] applies to each cell. *)
type fn = Neg | Abs | Sqrt | Exp | Log | Sin | Cos | Tan | Asin | Acos | Atan | Log10 | Log2 | Log1p | Expm1 | Cbrt | Sinh
  | Cosh | Tanh | Asinh | Acosh | Atanh | Sind | Cosd | Tand | Spacing

(** The sine, cosine and tangent of an angle in degrees, reduced exactly to [-45, 45] first: 0 and 1 exact at the multiples
    of 90, 1/2 at 30, 1 for the tangent at 45; a zero has the sign of C23's sinpi, cospi and tanpi. *)
val sind : float -> float
val cosd : float -> float
val tand : float -> float

(** The distance from |x| to the next float above it, MATLAB's eps(x); NaN for an infinity. *)
val spacing : float -> float

(** The cube root, correctly rounded: the nearest float to the real root, where the C library's is up to 3 ulps away. *)
val cbrt : float -> float

(** [map fn x]: [fn] of each cell of [x], in a new array: OCaml's [Float.neg], [Float.abs], the C library's sqrt, exp,
    log, sin, cos, tan, asin, acos, atan, log10, log2, log1p, expm1, sinh, cosh, tanh, asinh, acosh and atanh, as on
    one float, and [cbrt], [sind], [cosd], [tand] and [spacing]. *)
val map : fn -> floatarray -> floatarray

(** log(exp x + exp y), numpy's logaddexp, without overflow. *)
val log_add_exp : float -> float -> float

(** log(sum(exp x)) of the cells, without overflow, small terms kept beside the largest: -inf for none. *)
val log_sum_exp : floatarray -> float

(** What [one] does to a float: keep it in [lo, hi], a NaN kept; NaN made [by]; the step of Heaviside, [zero] at 0. *)
type pick = Clamp of float * float | Nan of float | Step of float

val one : pick -> float -> float

(** [one] of each cell, in a new array. *)
val pick : pick -> floatarray -> floatarray
val sum : floatarray -> float

(** [dot x y]: the sum of the products of [x] and [y], of one length, in the order of [sum], so that it gives the bits
    of [sum] on the array of the products, without making it. *)
val dot : floatarray -> floatarray -> float

(** [sum_along ~inner ~len ~outer x]: the sums along a dimension of [len] cells, with [inner] cells for the dimensions
    before it and [outer] after: [inner * outer] sums, each of its cells in order. *)
val sum_along : inner:int -> len:int -> outer:int -> floatarray -> floatarray

(** The same on integers, or [None] if one overflows. *)
val sum_along_ints : inner:int -> len:int -> outer:int -> int array -> int array option
(** A block of a matrix kept by columns: its cell (i, j), from 0, is [data.(offset + i + j * ld)]. *)
type block = { data : floatarray; offset : int; ld : int }

(** [!gemm ~rows ~cols ~inner ~trans ~sub ~threads out x y]: out, rows x cols, becomes x y, x being rows x inner and y
    inner x cols, or x y' when [trans], y then cols x inner; out minus that product when [sub]. Out shares no cell with x
    or y. From a library when the machine has one, each block first checked to lie inside its array, on at most
    [threads] threads, or as many as the library takes by itself for 0; the caller decides from what size a call is
    worth it. It says whether it did the work. Matmul's product, and the dense blocks of std/sparse's factorizations. *)
val gemm : (rows:int -> cols:int -> inner:int -> trans:bool -> sub:bool -> threads:int -> block -> block -> block -> bool) ref

val matmul : rows:int -> cols:int -> inner:int -> out:floatarray -> floatarray -> floatarray -> floatarray
(** The positions from 0 to [n], stably sorted by a comparison of two positions. [parallel] says that the comparison can run
    on several cores: it touches nothing and can't panic. *)
val sort_positions : ?parallel:bool -> int -> (int -> int -> int) -> int array

val transpose : rows:int -> cols:int -> floatarray -> floatarray
