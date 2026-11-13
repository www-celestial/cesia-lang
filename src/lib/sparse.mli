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
