(** The kernels of std/sparse, on matrices in compressed columns counted from 0: an ordering and LU's
    factorization. [pay n] counts n cells of work; [reserve n] the memory of n words, before a large array. *)

(** [valid ~m ~n p i]: [p] holds n + 1 offsets from 0 to the length of [i], never decreasing, and each row of [i] is from 0
    to m - 1. *)
val valid : m:int -> n:int -> int array -> int array -> bool

(** [permutation n q]: [q] holds each of 0 to n - 1 once. *)
val permutation : int -> int array -> bool

(** The order of elimination of a [valid] n x n pattern by approximate minimum degree on the pattern of a + a'. *)
val amd : pay:(int -> unit) -> int -> int array -> int array -> int array

(** [lu n ap ai ax q tol]: lp, li, lx of L (unit, its diagonal not kept), up, ui, ux of U (its diagonal last in each
    column) and pinv, p a q = L U; [None] when a is singular. *)
val lu :
  pay:(int -> unit) -> reserve:(int -> unit) -> int -> int array -> int array -> floatarray -> int array -> float ->
  (int array * int array * floatarray * int array * int array * floatarray * int array) option

(** A factorization by supernodes, with its order. *)
type factor

(** [Factor], or [Failed]: a pivot not above 0 for Cholesky, no pivot inside a front that passes the threshold test for
    LU; or [Memory words] when the factor and its work would take more words than the limit. *)
type outcome = Factor of factor | Failed | Memory of int

(** [cholesky n ap ai ax perm]: p a p' = L L' for a symmetric a, perm the order of elimination (AMD's), by supernodes
    whose dense blocks go to BLAS when the machine has it; only the lower triangle of p a p' is read. *)
val cholesky :
  pay:(int -> unit) -> reserve:(int -> unit) -> limit:int -> int -> int array -> int array -> floatarray -> int array ->
  outcome

(** [front_lu n ap ai ax perm tol]: p a q = L U, q = perm the order of AMD on a + a', by the supernodes of a + a', each
    front pivoting inside the rows it holds whole when the pivot is at least tol times the largest cell of its column. *)
val front_lu :
  pay:(int -> unit) -> reserve:(int -> unit) -> limit:int -> int -> int array -> int array -> floatarray -> int array ->
  float -> outcome

(** The cells the factor keeps, its zeros in blocks included. *)
val size : factor -> int

(** The x of a x = b, b of the factor's order. *)
val solve : factor -> floatarray -> floatarray
