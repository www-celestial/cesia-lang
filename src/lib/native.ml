open Types

(* A direct call doesn't share its arguments, so that measuring a variable leaves it owned. A native returning one of
   its inputs therefore creates the second reference here: only an owned list, struct or map has one to create, so a
   number, a text or one already shared never looks through the arguments, a sixth of the call of math.Abs. *)
let any (_ : ty array) = TA

let nat ?perm ?(params = [||]) ?(ret = any) ?(result = false) nname min_args max_args run =
  let run ctx (a : t array) =
    match run ctx a with
    | (Array { a_owned = true; _ } | Struct { r_owned = true; _ } | Dict { d_owned = true; _ }) as r when Array.memq r a ->
      Value.share r
    | r -> r
  in
  Native { nname; perm; params; min_args; max_args; ret_ty = ret; run; f1 = None; i2 = None; gives_result = result }

let int_native nname f =
  let whole ctx v =
    match v with
    | Int i -> i
    | Float x when Float.is_integer x && Float.abs x < 4e18 -> int_of_float x
    | _ -> Runtime.fail ctx Type (Messages.want_int nname (Value.describe v))
  in
  Native
    { nname; perm = None; params = [||]; min_args = 2; max_args = 2;
      ret_ty = (function [| TI; TI |] -> TI | _ -> TA);
      run = (fun ctx a -> Int (f ctx (whole ctx a.(0)) (whole ctx a.(1))));
      f1 = None; i2 = Some f; gives_result = false }

(* The return types inference can know. *)
let same_number (a : ty array) = match a with [| (TI | TF | TFA) as t |] -> t | _ -> TA
let float_of_number (a : ty array) = match a with [| (TI | TF) |] -> TF | [| TFA |] -> TFA | _ -> TA
let scalar_of_fa (a : ty array) = match a with [| TFA |] -> TF | _ -> TA
let fa_size (_ : ty array) = TFA
let same_fa (a : ty array) = match a with [| TFA |] -> TFA | _ -> TA

(* The line is built apart: showing a long value can let another fiber run. *)
let print ctx args =
  let w = ctx.w in
  let line = String.concat " " (Array.to_list (Array.map (Value.text_of ctx) args)) in
  Buffer.add_string w.out line;
  Buffer.add_char w.out '\n';
  if Buffer.length w.out > 65536 then Runtime.flush_out w;
  Missing

(* The standard output goes first, so that the two keep their order on a terminal. *)
let print_error ctx args =
  let w = ctx.w in
  Runtime.flush_out w;
  w.err (String.concat " " (Array.to_list (Array.map (Value.text_of ctx) args)) ^ "\n");
  Missing

(* A character starts at each byte that doesn't continue one, 10xxxxxx, and holds the bytes that do after it: in UTF-8,
   a code point. A text that isn't UTF-8 follows the same rule, everywhere: a byte that continues nothing belongs to the
   character before it, and those that begin the text are one character. Eight bytes at a time (SWAR): a byte that
   continues is 10xxxxxx, its high bit set and the next one clear, which [w land lnot (w lsl 1)] leaves at the high bit; a
   multiplication adds up those bits. *)
let[@inline] continues s i = Char.code s.[i] land 0xC0 = 0x80

let points_between s a b =
  let n = ref (if a = 0 && b > 0 && continues s 0 then 1 else 0) and k = ref a in
  while !k + 8 <= b do
    let w = String.get_int64_le s !k in
    let follow = Int64.logand (Int64.logand w (Int64.lognot (Int64.shift_left w 1))) 0x8080808080808080L in
    n := !n + 8 - Int64.to_int (Int64.shift_right_logical (Int64.mul (Int64.shift_right_logical follow 7) 0x0101010101010101L) 56);
    k := !k + 8
  done;
  for j = !k to b - 1 do
    if Char.code s.[j] land 0xC0 <> 0x80 then incr n
  done;
  !n

let code_points s = points_between s 0 (String.length s)

(* The text of each value, one after the other. *)
let str ctx args =
  let parts = Array.map (Value.text_of ctx) args in
  Runtime.build ctx ((Array.fold_left (fun n s -> n + String.length s) 0 parts / 8) + 1);
  Text (String.concat "" (Array.to_list parts))

let length v =
  match v with
  | Dict _ -> Trie.length v
  | Text s -> code_points s
  | Array a -> a.rows * a.cols
  | Struct r -> Trie.nvals r.fields
  | _ -> 1

(* What f gives for each key and value of a map, in the order of insertion. *)
let dict_items ctx name m f =
  let o = Dict.items ctx name m in
  let n = Array.length o / 2 in
  Runtime.build ctx n;
  Arrays.list (Array.init n (fun i -> f o.(2 * i) o.((2 * i) + 1)))

let key_name = Text "Key" and value_name = Text "Value"
let key_hash = Trie.hash key_name and value_hash = Trie.hash value_name
let pair_keys = Trie.names [| "Key"; "Value" |]

let dict_of_pairs ctx (a : t array) =
  let pair p =
    match p with
    | Dict _ when Trie.find p key_hash key_name != Undef && Trie.find p value_hash value_name != Undef ->
      [ Value.share (Trie.find p value_hash value_name); Trie.find p key_hash key_name ]
    | _ -> Runtime.fail ctx Type (Messages.dict_pair (Value.describe p))
  in
  match a with
  | [||] -> Dict.empty ()
  | [| Array x |] ->
    let rows = List.init (x.rows * x.cols) (fun k -> pair (Value.elt x k)) in
    Dict.of_items ctx (Array.of_list (List.rev (List.concat (List.rev rows))))
  | _ -> Runtime.fail ctx Type (Messages.dict_pair (Value.describe a.(0)))

let dict_literal ctx (a : t array) =
  if Array.length a mod 2 = 1 then Runtime.fail ctx Type (Messages.dict_pair (Value.describe a.(0)));
  Dict.of_items ctx (Array.map Value.share a)

let dim ctx name v =
  match v with
  | Int i when i >= 0 -> i
  | Float x when Float.is_integer x && x >= 0. && x < 4e18 -> int_of_float x
  | _ -> Runtime.fail ctx Type (Messages.bad_size name (Value.describe v))

(* The sizes from argument [at] on: one is a list of n. *)
let sizes_of ctx name (a : t array) at = Array.init (Array.length a - at) (fun k -> dim ctx name a.(at + k))

let max_dims = 32

let filled ctx value sizes =
  let n = Arrays.cells ctx sizes in
  Runtime.pay ctx n;
  Arrays.shaped sizes
    (match value with
     | Float x -> F (Runtime.alloc_float ctx n x)
     | Int i when n > 0 -> I (Runtime.alloc_ints ctx n i)
     | v -> V (Runtime.alloc_vals ctx n (Value.share v)))

(* A dimension of [x], from 1, given to [name]. *)
let dim_of ctx name x v =
  let n = Arrays.ndims x in
  match v with
  | Int d when d >= 1 && d <= n -> d
  | Float f when Float.is_integer f && f >= 1. && f <= float_of_int n -> int_of_float f
  | _ -> Runtime.fail ctx Index (Messages.dim_outside name n (Value.describe v))

let size ctx (a : t array) =
  let x = match a.(0) with Array x -> x | _ -> { rows = 1; cols = 1; store = V [||]; a_owned = false; a_tip = false; dims = Arrays.flat } in
  let sizes = Arrays.sizes x in
  if Array.length a = 1 || a.(1) == Missing then
    Array { rows = 1; cols = Array.length sizes; store = V (Array.map (fun n -> Int n) sizes); a_owned = true; a_tip = true; dims = Arrays.flat }
  else Int sizes.(dim_of ctx "Size" x a.(1) - 1)

(* value.Text(x, most): the text of x, cut at most characters with most. *)
let text ctx (a : t array) =
  if Array.length a = 1 || a.(1) == Missing then Text (Value.text_of ctx a.(0))
  else
    match a.(1) with
    | Int most when most >= 1 -> Text (Value.text_upto ctx most a.(0))
    | Float x when Float.is_integer x && x >= 1. && x < 4e18 -> Text (Value.text_upto ctx (int_of_float x) a.(0))
    | v -> Runtime.fail ctx Type (Messages.text_most (Value.describe v))

let reshape ctx (a : t array) =
  let sizes =
    match a.(0) with
    | Array s when s.rows * s.cols >= 1 -> Array.init (s.rows * s.cols) (fun k -> dim ctx "Reshape" (Value.elt s k))
    | v -> Runtime.fail ctx Type (Messages.reshape_shape (Value.describe v))
  in
  if Array.length sizes > max_dims then Runtime.fail ctx Type (Messages.too_many_dims (Array.length sizes));
  match a.(1) with
  | Array x ->
    let n = x.rows * x.cols in
    if Arrays.cells ctx sizes <> n then Runtime.fail ctx Type (Messages.reshape_size n sizes);
    Runtime.pay ctx n;
    (match Runtime.copy ctx a.(1) with
     | Array y -> Arrays.shaped sizes y.store
     | v -> v)
  | v -> Runtime.fail ctx Type (Messages.index_value (Value.describe v))

let is_ name test = name, nat name 1 1 (fun _ a -> Value.of_bool (test a.(0)))

let rec abs_value ctx v =
  match v with
  | Int i when i = min_int -> Runtime.fail ctx Math (Messages.overflow_neg (string_of_int i))
  | Int i -> Int (abs i)
  | Float x -> Float (Float.abs x)
  | True -> Int 1
  | False -> Int 0
  | Missing -> Missing
  | Array ({ store = F _; _ } as x) ->
    Runtime.build ctx (x.rows * x.cols);
    (match (Value.trim x).store with F d -> Arrays.like x (F (Kernels.map Kernels.Abs d)) | _ -> v)
  | Array _ -> elementwise ctx "Abs" abs_value v
  | _ -> Runtime.fail ctx Type (Messages.need_number "Abs" (Value.describe v))

and elementwise ctx _name scalar v =
  match v with
  | Array x ->
    Runtime.build ctx (x.rows * x.cols);
    Arrays.vals_like x (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k)))
  | _ -> scalar ctx v

(* A math function: float to float, element by element. *)
let math1 name f kernel =
  let rec go ctx v =
    match v with
    | Float x -> Float (f x)
    | Int i -> Float (f (float_of_int i))
    | True -> Float (f 1.)
    | False -> Float (f 0.)
    | Missing -> Missing
    | Array ({ rows; cols; store = F _; _ } as x) ->
      Runtime.build ctx (rows * cols);
      (match (Value.trim x).store with F d -> Arrays.like x (F (Kernels.map kernel d)) | _ -> v)
    | Array _ -> elementwise ctx name go v
    | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))
  in
  name,
  Native { nname = name; perm = None; params = [||]; min_args = 1; max_args = 1; ret_ty = float_of_number;
           run = (fun ctx a -> go ctx a.(0)); f1 = Some f; i2 = None; gives_result = false }

(* math.Clamp, math.Step and num.ReplaceNan: [one] of a number, a float array in one loop, another array cell by cell;
   [missing] for missing. *)
let picked ?(missing = Missing) name p one ctx v =
  let rec go ctx v =
    match v with
    | Int _ | Float _ -> one v
    | Missing -> missing
    | Array ({ store = F _; _ } as x) ->
      Runtime.build ctx (x.rows * x.cols);
      (match (Value.trim x).store with F d -> Arrays.like x (F (Kernels.pick p d)) | _ -> v)
    | Array _ -> elementwise ctx name go v
    | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))
  in
  go ctx v

let float_arg ctx name v =
  match v with Int i -> float_of_int i | Float x -> x | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))

(* A bound that x passes is given back as it is: an integer stays one. *)
let clamp ctx (a : t array) =
  let lo = float_arg ctx "Clamp" a.(0) and hi = float_arg ctx "Clamp" a.(1) in
  if not (lo <= hi) then Runtime.fail ctx Type (Messages.clamp_bounds (Value.describe a.(0)) (Value.describe a.(1)));
  picked "Clamp" (Kernels.Clamp (lo, hi))
    (fun v -> if Arith.lt ctx v a.(0) = True then a.(0) else if Arith.gt ctx v a.(1) = True then a.(1) else v) ctx a.(2)

let step ctx (a : t array) =
  let p = Kernels.Step (if Array.length a > 1 then float_arg ctx "Step" a.(1) else 0.5) in
  picked "Step" p (fun v -> Float (Kernels.one p (float_arg ctx "Step" v))) ctx a.(0)

let replace_nan ctx (a : t array) =
  let p = Kernels.Nan (float_arg ctx "ReplaceNan" a.(0)) in
  picked ~missing:a.(0) "ReplaceNan" p (function Float x when Float.is_nan x -> a.(0) | v -> v) ctx a.(1)

(* math.LogSumExp: of the cells of an array, or of two numbers, element by element for arrays. *)
let log_sum_exp ctx (a : t array) =
  if Array.length a = 2 then
    Arith.broadcast ctx
      (fun ctx x y ->
         match x, y with
         | Missing, _ | _, Missing -> Missing
         | _ -> Float (Kernels.log_add_exp (float_arg ctx "LogSumExp" x) (float_arg ctx "LogSumExp" y)))
      a.(0) a.(1)
  else
    match a.(0) with
    | Array ({ store = F _; _ } as x) ->
      Runtime.pay ctx (x.rows * x.cols);
      (match (Value.trim x).store with F d -> Float (Kernels.log_sum_exp d) | _ -> Missing)
    | Array x ->
      let n = x.rows * x.cols in
      Runtime.pay ctx n;
      let cells = Array.init n (Value.elt x) in
      if Array.mem Missing cells then Missing
      else Float (Kernels.log_sum_exp (Float.Array.map_from_array (float_arg ctx "LogSumExp") cells))
    | v -> Runtime.fail ctx Type (Messages.need_array "LogSumExp" (Value.describe v))

(* floor, ceil, round: an integer stays an integer. *)
let rounding name f =
  let rec go ctx v =
    match v with
    | Int _ -> v
    | Float x -> Float (f x)
    | True -> Int 1
    | False -> Int 0
    | Missing -> Missing
    | Array _ -> elementwise ctx name go v
    | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))
  in
  name, nat ~ret:same_number name 1 1 (fun ctx a -> go ctx a.(0))

let rec sign ctx v =
  match v with
  | Int i -> Int (compare i 0)
  | Float x -> Float (if Float.is_nan x then x else float_of_int (compare x 0.))
  | Missing -> Missing
  | Array _ -> elementwise ctx "Sign" sign v
  | _ -> Runtime.fail ctx Type (Messages.need_number "Sign" (Value.describe v))

let floats ctx name v =
  match v with
  | Array ({ store = F _; _ } as a) -> (match (Value.trim a).store with F d -> d | _ -> assert false)
  | Array a ->
    Runtime.reserve ctx (a.rows * a.cols);
    Float.Array.init (a.rows * a.cols) (fun k ->
        match Value.elt a k with
        | Int i -> float_of_int i
        | Float x -> x
        | x -> Runtime.fail ctx Type (Messages.need_number name (Value.describe x)))
  | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))

(* Matmul and Transpose take two dimensions. *)
let two ctx name (a : arr) = if Array.length a.dims > 0 then Runtime.fail ctx Type (Messages.two_dims name (Arrays.ndims a))

let shape_of ctx name v =
  match v with
  | Array a -> two ctx name a; a.rows, a.cols
  | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))

let matmul ctx (a : t array) =
  let r1, c1 = shape_of ctx "Matmul" a.(0) and r2, c2 = shape_of ctx "Matmul" a.(1) in
  if c1 <> r2 then Runtime.fail ctx Type (Messages.matmul_shape r1 c1 r2 c2);
  let out = Runtime.alloc_float ctx (Runtime.cells ctx r1 c2) 0. in
  Runtime.pay ctx (r1 * c1 * c2);
  let x = floats ctx "Matmul" a.(0) and y = floats ctx "Matmul" a.(1) in
  Arrays.of_float r1 c2 (Kernels.matmul ~rows:r1 ~cols:c2 ~inner:c1 ~out x y)

let transpose ctx (a : t array) =
  match a.(0) with
  | Array x ->
    two ctx "Transpose" x;
    let n = x.rows * x.cols in
    Runtime.build ctx n;
    let at k = let j = k / x.rows and i = k mod x.rows in (i * x.cols) + j in
    (match (Value.trim x).store with
     | F d -> Arrays.of_float x.cols x.rows (Kernels.transpose ~rows:x.rows ~cols:x.cols d)
     | I d ->
       let out = Array.make n 0 in
       Array.iteri (fun k v -> out.(at k) <- v) d;
       Arrays.of_ints x.cols x.rows out
     | V d ->
       let out = Array.make n Missing in
       if n > 0 then Array.iteri (fun k v -> out.(at k) <- Value.share v) d;
       Array { rows = x.cols; cols = x.rows; store = V out; a_owned = true; a_tip = true; dims = [||] })
  | v -> v

(* The first n columns of a matrix of numbers, n its rows, as floats: a copy the elimination can write, or None. *)
let leading ctx v =
  match v with
  | Array a when Array.length a.dims = 0 && a.rows <= a.cols ->
    let n = a.rows * a.rows in
    Runtime.reserve ctx n;
    let d = Float.Array.create n in
    let rec fill k =
      k >= n
      || (match Value.elt a k with
          | Int i -> Float.Array.set d k (float_of_int i); fill (k + 1)
          | Float x -> Float.Array.set d k x; fill (k + 1)
          | _ -> false)
    in
    (match a.store with
     | F src -> Float.Array.blit src 0 d 0 n; Some (a.rows, d)
     | _ -> if fill 0 then Some (a.rows, d) else None)
  | _ -> None

(* The dot product of two float arrays of one shape in one pass, with the bits of list.Sum(a * b); missing for anything
   else, which num.Dot then computes that way. *)
let dot ctx (a : t array) =
  match a.(0), a.(1) with
  | Array ({ store = F _; _ } as x), Array ({ store = F _; _ } as y) when Value.same_shape x y ->
    Runtime.pay ctx (x.rows * x.cols);
    (match (Value.trim x).store, (Value.trim y).store with F p, F q -> Float (Kernels.dot p q) | _ -> Missing)
  | _ -> Missing

(* The float cells of an array of floats, or the error of [name]. *)
let floats_of ctx name v =
  match v with
  | Array ({ store = F _; _ } as x) -> (match (Value.trim x).store with F d -> x, d | _ -> assert false)
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

(* The direction H g of L-BFGS by the two loops of Nocedal (1980), for optimize.Minimize: the [used] newest pairs (s, y)
   of the rings [ss] and [ys], the newest at place [newest], [rho] their 1 / s'y, and H0 = gamma I. The bits of the same
   loops written in Cesia with num.Dot, without their arrays for each step. *)
let lbfgs_direction ctx (a : t array) =
  let fail () = Runtime.fail ctx Type (Messages.need_array "direction" (Value.describe a.(0))) in
  let floats v = snd (floats_of ctx "direction" v) in
  let ring v = match v with Array x -> x | _ -> fail () in
  let g = floats a.(0) and ss = ring a.(1) and ys = ring a.(2) and rho = floats a.(3) in
  let used, newest, gamma = match a.(4), a.(5), a.(6) with Int u, Int k, Float c -> u, k, c | _ -> fail () in
  let m = Float.Array.length rho and n = Float.Array.length g in
  if used < 0 || used > m || newest < 1 || newest > m || ss.rows * ss.cols <> m || ys.rows * ys.cols <> m then fail ();
  let pair r k = let d = floats (Value.elt r (k - 1)) in if Float.Array.length d <> n then fail () else d in
  Runtime.pay ctx (4 * used * n);
  let q = Float.Array.copy g and alpha = Float.Array.make m 0. and k = ref newest in
  for _ = 1 to used do
    let y = pair ys !k in
    let al = Float.Array.get rho (!k - 1) *. Kernels.dot (pair ss !k) q in
    Float.Array.set alpha (!k - 1) al;
    for i = 0 to n - 1 do let p = al *. Float.Array.get y i in Float.Array.set q i (Float.Array.get q i -. p) done;
    k := if !k = 1 then m else !k - 1
  done;
  let r = Float.Array.map (fun v -> gamma *. v) q in
  for _ = 1 to used do
    k := if !k = m then 1 else !k + 1;
    let s = pair ss !k in
    let p = Float.Array.get rho (!k - 1) *. Kernels.dot (pair ys !k) r in let c = Float.Array.get alpha (!k - 1) -. p in
    for i = 0 to n - 1 do let p = c *. Float.Array.get s i in Float.Array.set r i (Float.Array.get r i +. p) done
  done;
  match a.(0) with Array x -> Arrays.like x (F r) | _ -> fail ()

(* The largest |x| of a float array, nan when one is nan, 0 for none: the size of a gradient, or of a simplex, for
   std/optimize, in one pass. A float always, so that inference knows it. *)
let largest ctx (a : t array) =
  let x, d = floats_of ctx "largest" a.(0) in
  Runtime.pay ctx (x.rows * x.cols);
  let m = ref 0. in
  for i = 0 to Float.Array.length d - 1 do
    let v = Float.abs (Float.Array.get d i) in
    if v > !m || Float.is_nan v then m := v
  done;
  Float !m

(* num's dot for std/optimize, whose arrays are floats of one shape: a float always, or an error. *)
let dot_floats ctx (a : t array) =
  let x, p = floats_of ctx "dot" a.(0) and y, q = floats_of ctx "dot" a.(1) in
  if not (Value.same_shape x y) then Runtime.fail ctx Type (Messages.shape (Arrays.sizes x) (Arrays.sizes y));
  Runtime.pay ctx (x.rows * x.cols);
  Float (Kernels.dot p q)

(* std/sparse's kernels: a Matrix's arrays, counted from 1, checked and counted from 0 for Sparse, its results from 1
   again. Arrays that don't fit together, as a Matrix built by hand can hold, fail the call: no read leaves them. *)
let sparse_ints ctx name v =
  match v with
  | Array ({ store = I _; _ } as a) -> (match (Value.trim a).store with I d -> Array.map pred d | _ -> [||])
  | Array a when a.rows * a.cols = 0 -> [||]
  | _ -> Runtime.fail ctx Type (Messages.sparse_bad name)

let sparse_columns ctx name (a : t array) =
  let n = match a.(0) with Int n when n >= 0 -> n | _ -> Runtime.fail ctx Type (Messages.sparse_bad name) in
  let p = sparse_ints ctx name a.(1) and i = sparse_ints ctx name a.(2) in
  if not (Sparse.valid ~m:n ~n p i) then Runtime.fail ctx Type (Messages.sparse_bad name);
  n, p, i

let sparse_values ctx name n v =
  let x = floats ctx name v in
  if Float.Array.length x <> n then Runtime.fail ctx Type (Messages.sparse_bad name);
  x

let sparse_order ctx name n v =
  let q = sparse_ints ctx name v in
  if not (Sparse.permutation n q) then Runtime.fail ctx Type (Messages.sparse_bad name);
  q

let from1 (x : int array) = Arrays.of_ints 1 (Array.length x) (Array.map succ x)

(* ordering(n, start, index): the order of AMD, from 1. *)
let sparse_ordering ctx (a : t array) =
  let n, p, i = sparse_columns ctx "ordering" a in
  Runtime.pay ctx (Array.length i + n);
  Runtime.reserve ctx ((8 * Array.length i) + (20 * n));
  from1 (Sparse.amd ~pay:(Runtime.pay ctx) n p i)

(* luFactor(n, start, index, values, q, tol): [lstart, lindex, lvalues, ustart, uindex, uvalues, pinv], or missing when
   a is singular. *)
let sparse_lu ctx (a : t array) =
  let n, p, i = sparse_columns ctx "luFactor" a in
  let x = sparse_values ctx "luFactor" (Array.length i) a.(3) and q = sparse_order ctx "luFactor" n a.(4) in
  let tol = match a.(5) with Float t when t >= 0. && t <= 1. -> t | _ -> Runtime.fail ctx Type (Messages.sparse_bad "luFactor") in
  match Sparse.lu ~pay:(Runtime.pay ctx) ~reserve:(Runtime.reserve ctx) n p i x q tol with
  | None -> Missing
  | Some (lp, li, lx, up, ui, ux, pinv) ->
    let floats x = Arrays.of_float 1 (Float.Array.length x) x in
    Arrays.list [| from1 lp; from1 li; floats lx; from1 up; from1 ui; floats ux; from1 pinv |]

(* What cholesky and luFront give: a function that gives the x of a x = b, the factor of a inside it; missing when the
   factorization fails; the bytes it would take when that is past the memory limit. *)
let sparse_factor n = function
  | Sparse.Failed -> Missing
  | Sparse.Memory words -> Int (8 * words)
  | Sparse.Factor f ->
    nat "solve" 1 1 (fun ctx b ->
        let b = floats ctx "solve" b.(0) in
        if Float.Array.length b <> n then Runtime.fail ctx Type (Messages.sparse_bad "solve");
        Runtime.pay ctx (2 * Sparse.size f);
        Runtime.reserve ctx (3 * n);
        Arrays.of_float 1 n (Sparse.solve f b))

(* cholesky(n, start, index, values, perm): Cholesky's factorization by supernodes, as sparse_factor gives it. *)
let sparse_cholesky ctx (a : t array) =
  let n, p, i = sparse_columns ctx "cholesky" a in
  let x = sparse_values ctx "cholesky" (Array.length i) a.(3) and q = sparse_order ctx "cholesky" n a.(4) in
  let limit = ctx.w.limits.memory_words in
  sparse_factor n (Sparse.cholesky ~pay:(Runtime.pay ctx) ~reserve:(Runtime.reserve ctx) ~limit n p i x q)

(* luFront(n, start, index, values, perm, tol): LU's factorization by the supernodes of a + a', as sparse_factor gives
   it. *)
let sparse_front ctx (a : t array) =
  let n, p, i = sparse_columns ctx "luFront" a in
  let x = sparse_values ctx "luFront" (Array.length i) a.(3) and q = sparse_order ctx "luFront" n a.(4) in
  let tol =
    match a.(5) with Float t when t >= 0. && t <= 1. -> t | _ -> Runtime.fail ctx Type (Messages.sparse_bad "luFront")
  in
  let limit = ctx.w.limits.memory_words in
  sparse_factor n (Sparse.front_lu ~pay:(Runtime.pay ctx) ~reserve:(Runtime.reserve ctx) ~limit n p i x q tol)

(* num's Gaussian elimination with partial pivoting, on the square of the first columns of m: at each column the row
   of the largest element in absolute value comes up (the first of equals), then each row below loses the multiple of
   it that makes its element 0, the multiplier kept there. The operations of the textbook in its order, as num's code
   in Cesia did them, so the same bits. {Singular, Lu, Perm, Sign}, Singular when a pivot is under 1e-14 in absolute
   value; or missing when m is no matrix of numbers with as many columns as rows or more. *)
let lu_factor ctx (a : t array) =
  match leading ctx a.(0) with
  | None -> Missing
  | Some (n, d) ->
    Runtime.pay ctx ((n * n * n / 3) + n);
    let perm = Array.init n (fun k -> k + 1) and sign = ref 1. and ok = ref true and col = ref 0 in
    while !ok && !col < n do
      let k = !col in
      let ck = k * n in
      let pivot = ref k in
      for r = k + 1 to n - 1 do
        if Float.abs (Float.Array.get d (ck + r)) > Float.abs (Float.Array.get d (ck + !pivot)) then pivot := r
      done;
      let p = !pivot in
      (* As num's code, a test of < 1e-14: a NaN pivot is no singular matrix, and the NaN goes on to the answer. *)
      if Float.abs (Float.Array.get d (ck + p)) < 1e-14 then ok := false
      else begin
        if p <> k then begin
          sign := -. !sign;
          for c = 0 to n - 1 do
            let x = Float.Array.get d ((c * n) + k) in
            Float.Array.set d ((c * n) + k) (Float.Array.get d ((c * n) + p));
            Float.Array.set d ((c * n) + p) x
          done;
          let q = perm.(k) in
          perm.(k) <- perm.(p);
          perm.(p) <- q
        end;
        (* The multipliers of the rows below, then each column right of k loses them times its element of row k: each
           element gets the operations it got row by row, in loops that read memory in its order. *)
        let pk = Float.Array.get d (ck + k) in
        for r = k + 1 to n - 1 do
          Float.Array.set d (ck + r) (Float.Array.get d (ck + r) /. pk)
        done;
        for c = k + 1 to n - 1 do
          let cc = c * n in
          let top = Float.Array.get d (cc + k) in
          for r = k + 1 to n - 1 do
            let f = Float.Array.get d (ck + r) in
            if f <> 0. then (let p = f *. top in Float.Array.set d (cc + r) (Float.Array.get d (cc + r) -. p))
          done
        done;
        incr col
      end
    done;
    Trie.record (Trie.names [| "Singular"; "Lu"; "Perm"; "Sign" |])
      [| Value.of_bool (not !ok); Arrays.of_float n n d; Arrays.of_ints 1 n perm; Float (if !ok then !sign else 0.) |]

(* The x of m x = b from lu_factor's Lu and Perm, by two triangular solves: b an array of n numbers, a row or a column,
   gives x in its shape; b a matrix of n rows, x with a column for each of its columns. Missing for another b. *)
let lu_solve ctx (a : t array) =
  match a.(0), a.(1), a.(2) with
  | Array l, Array p, Array b when Array.length b.dims = 0 && l.rows = l.cols && p.rows * p.cols = l.rows ->
    let n = l.rows in
    let vector = b.rows * b.cols = n && (b.rows = 1 || b.cols = 1) in
    if (not vector) && b.rows <> n then Missing
    else begin
      let cols = if vector then 1 else b.cols in
      Runtime.reserve ctx (n * cols);
      let x = Float.Array.create (n * cols) in
      let lu = floats ctx "Solve" a.(0) in
      let perm = Array.init n (fun k -> match Value.elt p k with Int i when i >= 1 && i <= n -> i - 1 | _ -> -1) in
      let rec fill k =
        k >= n * cols
        || (let i = perm.(k mod n) in
            i >= 0
            && (match Value.elt b ((k / n * n) + i) with
                | Int v -> Float.Array.set x k (float_of_int v); fill (k + 1)
                | Float v -> Float.Array.set x k v; fill (k + 1)
                | _ -> false))
      in
      if not (fill 0) then Missing
      else begin
        Runtime.pay ctx (n * n * cols);
        for c = 0 to cols - 1 do
          let o = c * n in
          for col = 0 to n - 2 do
            let xc = Float.Array.get x (o + col) in
            for r = col + 1 to n - 1 do
              let f = Float.Array.get lu ((col * n) + r) in
              if f <> 0. then (let p = f *. xc in Float.Array.set x (o + r) (Float.Array.get x (o + r) -. p))
            done
          done;
          for r = n - 1 downto 0 do
            let s = ref (Float.Array.get x (o + r)) in
            for k = r + 1 to n - 1 do
              let p = Float.Array.get lu ((k * n) + r) *. Float.Array.get x (o + k) in s := !s -. p
            done;
            Float.Array.set x (o + r) (!s /. Float.Array.get lu ((r * n) + r))
          done
        done;
        if vector then Arrays.of_float b.rows b.cols x else Arrays.of_float n cols x
      end
    end
  | _ -> Missing

let sum ctx v =
  match v with
  | Array ({ rows; cols; store = F _; _ } as x) ->
    Runtime.pay ctx (rows * cols);
    (match (Value.trim x).store with F d -> Float (Kernels.sum d) | _ -> v)
  | Array { rows; cols; store = I d; _ } ->
    Runtime.pay ctx (rows * cols);
    let acc = ref 0 in
    for k = 0 to (rows * cols) - 1 do acc := Arith.add_int ctx !acc d.(k) done;
    Int !acc
  | Array x ->
    let n = x.rows * x.cols in
    Runtime.pay ctx n;
    let acc = ref (Int 0) in
    for k = 0 to n - 1 do acc := Arith.add ctx !acc (Value.elt x k) done;
    !acc
  | True -> Int 1
  | False -> Int 0
  | _ -> v

let mean ctx v =
  match v with
  | Array x when x.rows * x.cols = 0 -> Float nan
  | Array x -> Arith.div ctx (sum ctx v) (Int (x.rows * x.cols))
  | _ -> v

(* Sums along dimension [d]: the result has the other dimensions. A cell of it adds [len] cells of [x], each [inner] after
   the one before, in order, so that the rounding doesn't depend on the cores. *)
let sum_along ctx name v d =
  let x = (match v with Array x -> Value.trim x | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))) in
  let sizes = Arrays.sizes x in
  let k = dim_of ctx name x d - 1 in
  let inner = Array.fold_left ( * ) 1 (Array.sub sizes 0 k) and len = sizes.(k) in
  let outer = Array.fold_left ( * ) 1 (Array.sub sizes (k + 1) (Array.length sizes - k - 1)) in
  let rest = Array.append (Array.sub sizes 0 k) (Array.sub sizes (k + 1) (Array.length sizes - k - 1)) in
  let cells = inner * outer in
  Runtime.pay ctx (x.rows * x.cols);
  Runtime.build ctx cells;
  let store =
    match x.store with
    | F d -> F (Kernels.sum_along ~inner ~len ~outer d)
    | I d ->
      (match Kernels.sum_along_ints ~inner ~len ~outer d with
       | Some s -> I s
       | None ->
         (* An overflow: the cell by cell sum meets it and raises its error. *)
         for o = 0 to cells - 1 do
           let acc = ref 0 and at = (o mod inner) + (o / inner * inner * len) in
           for b = 0 to len - 1 do acc := Arith.add_int ctx !acc d.(at + (b * inner)) done
         done;
         I [||])
    | V _ ->
      let out = Array.make cells (Int 0) in
      for o = 0 to cells - 1 do
        let at = (o mod inner) + (o / inner * inner * len) in
        for b = 0 to len - 1 do out.(o) <- Arith.add ctx out.(o) (Value.elt x (at + (b * inner))) done
      done;
      Arrays.store_of out
  in
  Arrays.shaped rest store, len

let sum_of ctx (a : t array) = if Array.length a = 1 || a.(1) == Missing then sum ctx a.(0) else fst (sum_along ctx "Sum" a.(0) a.(1))

let mean_of ctx (a : t array) =
  if Array.length a = 1 || a.(1) == Missing then mean ctx a.(0)
  else
    match sum_along ctx "Mean" a.(0) a.(1) with
    | Array ({ store = F d; _ } as s), len -> Arrays.like s (F (Kernels.right Kernels.Div d (float_of_int len)))
    | Array s, len ->
      Arrays.vals_like s (Array.init (s.rows * s.cols) (fun k -> Arith.div ctx (Value.elt s k) (Int len)))
    | v, _ -> v

(* min and max: the whole array with one argument, element by element with two. *)
let best name better fbetter ctx (a : t array) =
  let pick ctx x y =
    match x, y with
    | Missing, _ | _, Missing -> Missing
    | _ -> if better ctx y x = True then y else x
  in
  if Array.length a = 2 then Arith.broadcast ctx pick a.(0) a.(1)
  else
    match a.(0) with
    | Array ({ store = F _; _ } as x) when x.rows * x.cols > 0 ->
      Runtime.pay ctx (x.rows * x.cols);
      (match (Value.trim x).store with
       | F d ->
         let acc = ref (Float.Array.get d 0) in
         Float.Array.iter (fun y -> if fbetter y !acc then acc := y) d;
         Float !acc
       | _ -> a.(0))
    | Array x ->
      let n = x.rows * x.cols in
      if n = 0 then Runtime.fail ctx Type (Messages.empty_array name);
      Runtime.pay ctx n;
      let acc = ref (Value.elt x 0) in
      for k = 1 to n - 1 do acc := pick ctx !acc (Value.elt x k) done;
      Value.share !acc
    | v -> v

let mask_all name stop ctx (a : t array) =
  match a.(0) with
  | Array x ->
    let n = x.rows * x.cols in
    Runtime.pay ctx n;
    let rec go k =
      if k >= n then not stop
      else
        match Value.elt x k with
        | True -> if stop then true else go (k + 1)
        | False | Missing -> if stop then go (k + 1) else false
        | v -> Runtime.fail ctx Type (Messages.condition (Value.describe v))
    in
    Value.of_bool (go 0)
  | True -> True
  | False | Missing -> False
  | v -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))

let text_arg ctx name v =
  match v with
  | Text s -> s
  | _ -> Runtime.fail ctx Type (Messages.need_text name (Value.describe v))

let flag_arg ctx name (a : t array) k =
  match if k < Array.length a then a.(k) else Undef with
  | True -> true
  | Undef | Missing | False -> false
  | v -> Runtime.fail ctx Type (Messages.need_flag name (Value.describe v))

let lows = 0x7F7F7F7F7F7F7F7FL
let ones = 0x0101010101010101L

(* The high bit of each byte of a word that is zero, and of no other: the test of Hacker's Delight, 6-1, exact. *)
let[@inline] zero_bytes t = Int64.lognot (Int64.logor (Int64.logor (Int64.add (Int64.logand t lows) lows) t) lows)

(* How common a byte is in text and code, the most common first, then the letters by their frequency in English: a byte
   of none of them, a capital, a digit, is the rarest, 0. *)
let ranks =
  let r = Bytes.make 256 '\000' in
  String.iteri (fun i c -> Bytes.set r (Char.code c) (Char.chr (33 - i))) " \n().,etaoinsrhldcumfpgwybvkxjqz";
  Bytes.to_string r

(* Crochemore and Perrin's Two-Way search, "Two-way string-matching", J. ACM 38(3):650-674, 1991, as glibc's memmem
   and Rust's str::find: linear time, constant space, for the parts of 32 bytes or more, where the plain search could be
   quadratic. Bytes are folded as they are read: a long part is never copied. *)
let[@inline] low fold c = if fold then Char.lowercase_ascii c else c

(* The start and the period of the largest suffix of [part], by the order of the bytes or, with [rev], its reverse: the
   paper's maximal suffix, as glibc's critical_factorization computes it. *)
let max_suffix fold part rev =
  let m = String.length part in
  let rec go ms j k p =
    if j + k >= m then ms + 1, p
    else
      let a = low fold part.[j + k] and b = low fold part.[ms + k] in
      if a = b then if k = p then go ms (j + p) 1 p else go ms j (k + 1) p
      else if (a < b) <> rev then go ms (j + k) 1 (j + k - ms)
      else go j (j + 1) 1 1
  in
  go (-1) 0 1 1

(* The first place from [j] whose byte, folded, is [c], or the end: past one that isn't, eight bytes at a time as
   [find_from] does. *)
let rec next fold s c mask want j =
  if j >= String.length s || low fold s.[j] = c then j
  else if j + 9 <= String.length s && Int64.equal (zero_bytes (Int64.logxor (Int64.logor (String.get_int64_le s (j + 1)) mask) want)) 0L then next fold s c mask want (j + 9)
  else next fold s c mask want (j + 1)

(* The part is cut where the shorter of its two maximal suffixes starts, [crit]: a window compares the right half from
   left to right, then the left half from right to left. When the whole part has the period [p] of its right half, a
   window after a miss in the left half remembers in [mem] how many of its first bytes are known to match. A window with
   nothing remembered first moves to the next place of the rarest byte of the part, by [ranks]: the places it skips
   start no match, and a byte of [s] is still compared at most once in a right half, so the search compares at most
   2 (n - from) bytes and skips each at most once. [long_finder] does the work on the part once, for many searches. *)
let long_finder fold s part =
  let n = String.length s and m = String.length part in
  let c1, p1 = max_suffix fold part false and c2, p2 = max_suffix fold part true in
  let crit, p = if c2 < c1 then c1, p1 else c2, p2 in
  let rec same i = i >= crit || (low fold part.[i] = low fold part.[i + p] && same (i + 1)) in
  let periodic = same 0 in
  let period = if periodic then p else (if crit > m - crit then crit else m - crit) + 1 in
  let rank k = ranks.[Char.code (low fold part.[k])] in
  let rec rarest k r = if k >= m || rank r = '\000' then r else rarest (k + 1) (if rank k < rank r then k else r) in
  let r = rarest 1 0 in
  let c = low fold part.[r] in
  let mask = if fold && c >= 'a' && c <= 'z' then Int64.mul 0x20L ones else 0L in
  let want = Int64.mul (Int64.of_int (Char.code c)) ones in
  let rec go j mem =
    let j = if mem = 0 then next fold s c mask want (j + r) - r else j in
    if j > n - m then -1
    else begin
      let i = ref (if crit > mem then crit else mem) in
      while !i < m && low fold part.[!i] = low fold s.[j + !i] do incr i done;
      if !i < m then go (j + !i - crit + 1) 0
      else begin
        let i = ref (crit - 1) in
        while !i >= mem && low fold part.[!i] = low fold s.[j + !i] do decr i done;
        if !i < mem then j else go (j + period) (if periodic then m - period else 0)
      end
    end
  in
  fun from -> if m > n - from then -1 else go from 0

(* It exits before any work if the part can't fit: its callers pay for all it does by paying for the bytes of [s] it
   could read. *)
let find_long fold s part from = if String.length part > String.length s - from then -1 else long_finder fold s part from

(* The first position of [part] in [s] from byte [from], or -1. [part] isn't empty. With [fold], the ASCII letters match
   in either case, in both. The rarest byte of [part], by [ranks], is looked for eight bytes at a time (SWAR): the word
   xor that byte repeated has a zero byte where it is; a letter is or'ed with 0x20 in each byte first, which turns its
   capital into it and no other byte. Each place found is then compared whole. *)
(* One byte, as most parts are, a line end or a colon: eight bytes at a time, with no closure made. *)
let rec byte_from s want c i n =
  if i + 8 > n then if i >= n then -1 else if s.[i] = c then i else byte_from s want c (i + 1) n
  else if Int64.equal (zero_bytes (Int64.logxor (String.get_int64_le s i) want)) 0L then
    (if i + 16 > n && i + 8 < n then byte_from s want c (n - 8) n else byte_from s want c (i + 8) n)
  else if s.[i] = c then i else byte_from s want c (i + 1) n

let find_from ?(fold = false) s part from =
  if String.length part >= 32 then find_long fold s part from
  else if String.length part = 1 && not fold then byte_from s (Int64.mul (Int64.of_int (Char.code part.[0])) ones) part.[0] from (String.length s)
  else begin
    let part = if fold then String.lowercase_ascii part else part in
    let n = String.length s and m = String.length part in
    let at i = if fold then Char.lowercase_ascii s.[i] else s.[i] in
    let rank c = ranks.[Char.code c] in
    let r = ref 0 in
    String.iteri (fun k c -> if rank c < rank part.[!r] then r := k) part;
    let r = !r in
    let c = part.[r] in
    let mask = if fold && c >= 'a' && c <= 'z' then Int64.mul 0x20L ones else 0L in
    let want = Int64.mul (Int64.of_int (Char.code c)) ones in
    let rec same p k = k >= m || (at (p + k) = part.[k] && same p (k + 1)) in
    let rec bytes j stop = if j >= stop then -1 else if at j = c && j - r + m <= n && same (j - r) 0 then j - r else bytes (j + 1) stop in
    let rec words i =
      if i + 8 > n then bytes i n
      else if Int64.equal (zero_bytes (Int64.logxor (Int64.logor (String.get_int64_le s i) mask) want)) 0L then words (i + 8)
      else match bytes i (i + 8) with -1 -> words (i + 8) | p -> p
    in
    words (from + r)
  end

(* The searches of [part] in [s] from one byte then another, as [count] and [pieces] make: a long part that fits in [s]
   is worked on once, which they pay for by paying for all of [s]. *)
let finder s part =
  if String.length part >= 32 && String.length part <= String.length s then long_finder false s part else find_from s part

(* The pieces of [s] between the occurrences of [sep]. *)
let pieces s sep =
  let find = finder s sep in
  let rec go from acc =
    match find from with
    | -1 -> List.rev (String.sub s from (String.length s - from) :: acc)
    | p -> go (p + String.length sep) (String.sub s from (p - from) :: acc)
  in
  go 0 []

let non_empty ctx name part =
  if part = "" then Runtime.fail ctx Type (Messages.empty_text name);
  part

let split ctx (a : t array) =
  let sep = non_empty ctx "Split" (text_arg ctx "Split" a.(0)) and s = text_arg ctx "Split" a.(1) in
  Runtime.build ctx ((String.length s / 8) + 1);
  let items = Array.of_list (List.map (fun p -> Text p) (pieces s sep)) in
  Array { rows = 1; cols = Array.length items; store = V items; a_owned = true; a_tip = true; dims = [||] }

(* The buffer is sized first, from the texts in the list and 8 bytes for each other value, so a list of texts is copied
   once into it, never into a buffer that doubles. *)
let join ctx (a : t array) =
  let sep = text_arg ctx "Join" a.(0) in
  match a.(1) with
  | Array x ->
    let n = x.rows * x.cols in
    Runtime.build ctx n;
    let size = ref (String.length sep * max 0 (n - 1)) in
    for k = 0 to n - 1 do
      size := !size + match Value.elt x k with Text s -> String.length s | _ -> 8
    done;
    let b = Buffer.create !size in
    for k = 0 to n - 1 do
      if k > 0 then Buffer.add_string b sep;
      let text = Value.text_of ctx (Value.elt x k) in
      Runtime.reserve ctx ((String.length text / 8) + 1);
      Buffer.add_string b text
    done;
    Text (Buffer.contents b)
  | v -> Runtime.fail ctx Type (Messages.need_array "Join" (Value.describe v))

(* The byte where character [k] starts, counting from 0, or the length of [s] past the end. *)
let byte_of_point s k =
  let n = String.length s in
  let rec go i left =
    if i >= n then i
    else if continues s i then go (i + 1) left
    else if left = 0 then i
    else go (i + 1) (left - 1)
  in
  if n > 0 && continues s 0 then (if k = 0 then 0 else go 0 (k - 1)) else go 0 k

(* The code point of the character at byte [i], and its bytes: U+FFFD for one that is no UTF-8. *)
let char_at s i =
  let n = String.length s and c = Char.code s.[i] in
  if c < 0x80 && (i + 1 >= n || not (continues s (i + 1))) then c, 1
  else begin
    (* A code point of UTF-8 holds the bytes that continue it: only those after it can make it longer, and no UTF-8. *)
    let d = String.get_utf_8_uchar s i in
    let valid = Uchar.utf_decode_is_valid d in
    let first = i + if valid then Uchar.utf_decode_length d else 1 in
    let j = ref first in
    while !j < n && continues s !j do incr j done;
    (if valid && !j = first then Uchar.to_int (Uchar.utf_decode_uchar d) else 0xFFFD), !j - i
  end

let slice ctx (a : t array) =
  let first = Arrays.whole_index ctx a.(0) and last = Arrays.whole_index ctx a.(1) in
  let s = text_arg ctx "Slice" a.(2) in
  let n = code_points s in
  if first < 1 then Runtime.fail ctx Index (Messages.text_outside first n "characters");
  if last > n then Runtime.fail ctx Index (Messages.text_outside last n "characters");
  if last < first then Text ""
  else begin
    Runtime.build ctx ((String.length s / 8) + 1);
    let start = byte_of_point s (first - 1) in
    Text (String.sub s start (byte_of_point s last - start))
  end

let replace ctx (a : t array) =
  let old_text = non_empty ctx "Replace" (text_arg ctx "Replace" a.(0)) in
  let by = text_arg ctx "Replace" a.(1) and s = text_arg ctx "Replace" a.(2) in
  let parts = pieces s old_text in
  let size = String.length s + (List.length parts * String.length by) in
  Runtime.build ctx ((size / 8) + 1);
  Text (String.concat by parts)

(* A sign, digits, then optionally a fraction and an exponent: nothing else reads as a number. *)
let number v =
  let n = String.length v in
  let digits i =
    let j = ref i in
    while !j < n && v.[!j] >= '0' && v.[!j] <= '9' do incr j done;
    !j
  in
  let sign i = if i < n && (v.[i] = '-' || v.[i] = '+') then i + 1 else i in
  let start = sign 0 in
  let whole = digits start in
  let part_end =
    if whole = start then -1
    else if whole < n && v.[whole] = '.' then
      (let e = digits (whole + 1) in
       if e = whole + 1 then -1 else e)
    else whole
  in
  let stop =
    if part_end >= 0 && part_end < n && (v.[part_end] = 'e' || v.[part_end] = 'E') then
      (let exp = sign (part_end + 1) in
       let e = digits exp in
       if e = exp then -1 else e)
    else part_end
  in
  if stop <> n then Missing
  else if stop = whole then
    match int_of_string_opt v with
    | Some i -> Int i
    | None -> Float (float_of_string v)
  else Float (float_of_string v)

(* A text from a code point: the only way to write a line end or a tab, since texts have no escapes. *)
let char ctx (a : t array) =
  match a.(0) with
  | Int i when Uchar.is_valid i ->
    let b = Buffer.create 4 in
    Buffer.add_utf_8_uchar b (Uchar.of_int i);
    Text (Buffer.contents b)
  | v -> Runtime.fail ctx Type (Messages.bad_char (Value.describe v))

(* String.trim gives the text back when there is nothing to take off: only a real copy reserves its memory. *)
let trim ctx (a : t array) =
  let s = text_arg ctx "Trim" a.(0) in
  Runtime.pay_bytes ctx (String.length s);
  let space c = c = ' ' || c = '\012' || c = '\n' || c = '\r' || c = '\t' in
  if s <> "" && (space s.[0] || space s.[String.length s - 1]) then Runtime.reserve ctx ((String.length s / 8) + 1);
  Text (String.trim s)

(* An integer is written from its digits, which a float would round past 2^53. *)
let decimals ctx (a : t array) =
  let n =
    match a.(0) with
    | Int n when n >= 0 && n <= 20 -> n
    | v -> Runtime.fail ctx Type (Messages.decimals_count (Value.describe v))
  in
  match a.(1) with
  | Int i -> Text (if n = 0 then string_of_int i else string_of_int i ^ "." ^ String.make n '0')
  | Float x ->
    (* printf rounds the exact value of the float, and a half to even: a true half goes away from zero here, as
       math.Round does. It is one when x times 10^n, exact (fma says so), ends in .5. What rounds to zero has no sign. *)
    let unsigned t =
      let rest = String.sub t 1 (String.length t - 1) in
      if t.[0] = '-' && String.for_all (fun c -> c = '0' || c = '.') rest then rest else t
    in
    let p = float_of_string ("1e" ^ string_of_int n) in
    let y = x *. p in
    if Float.abs (y -. Float.trunc y) = 0.5 && Float.fma x p (-.y) = 0. then begin
      let r = Float.round y in
      let digits = Printf.sprintf "%.0f" (Float.abs r) in
      let digits = String.make (max 0 (n + 1 - String.length digits)) '0' ^ digits in
      let k = String.length digits - n in
      let sign = if r < 0. then "-" else "" in
      Text (if n = 0 then sign ^ digits else sign ^ String.sub digits 0 k ^ "." ^ String.sub digits k n)
    end
    else Text (unsigned (Printf.sprintf "%.*f" n x))
  | v -> Runtime.fail ctx Type (Messages.need_number "text.Decimals" (Value.describe v))

(* Valid UTF-8, as RFC 3629 defines it: no overlong form, no surrogate, nothing past U+10FFFF. Eight bytes of ASCII at a
   time, by one test of their high bits; past the first byte that isn't ASCII, the decoder of the Stdlib, which follows
   the same rules. *)
let is_utf8 s =
  let n = String.length s in
  let rec go i =
    if i + 8 <= n && Int64.logand (String.get_int64_le s i) 0x8080808080808080L = 0L then go (i + 8)
    else if i >= n then true
    else if Char.code s.[i] < 128 then go (i + 1)
    else begin
      let d = String.get_utf_8_uchar s i in
      Uchar.utf_decode_is_valid d && go (i + Uchar.utf_decode_length d)
    end
  in
  go 0

(* The occurrences of [part], not empty, in [s], without overlaps. A part of one byte is counted eight bytes at a time:
   the word xor the byte repeated is zero at each byte equal to it, and the classic test of a zero byte sets the high bit
   of exactly those, which a multiplication adds up (SWAR, SIMD within a register). *)
let count part s =
  let n = String.length s in
  if String.length part = 1 then begin
    let c = Int64.mul (Int64.of_int (Char.code part.[0])) ones in
    let total = ref 0 and i = ref 0 in
    while !i + 8 <= n do
      let y = zero_bytes (Int64.logxor (String.get_int64_le s !i) c) in
      total := !total + Int64.to_int (Int64.shift_right_logical (Int64.mul (Int64.shift_right_logical y 7) ones) 56);
      i := !i + 8
    done;
    for j = !i to n - 1 do
      if s.[j] = part.[0] then incr total
    done;
    !total
  end else begin
    let find = finder s part in
    let rec go from k = match find from with -1 -> k | p -> go (p + String.length part) (k + 1) in
    go 0 0
  end

let text_natives =
  let pay ctx s = Runtime.pay_bytes ctx (String.length s) in
  let on_text name f =
    name, nat name 1 1 (fun ctx a ->
        let s = text_arg ctx name a.(0) in
        pay ctx s;
        f s)
  in
  let test2 name f =
    name, nat name 2 2 (fun ctx a ->
        let p = text_arg ctx name a.(0) and s = text_arg ctx name a.(1) in
        pay ctx s;
        Value.of_bool (f p s))
  in
  [ "Split", nat "Split" 2 2 split;
    "Decimals", nat ~params:[| "n"; "x" |] "Decimals" 2 2 decimals;
    "Join", nat "Join" 2 2 join;
    "Slice", nat "Slice" 3 3 slice;
    "Replace", nat "Replace" 3 3 replace;
    "Char", nat "Char" 1 1 char;
    "Trim", nat "Trim" 1 1 trim;
    "Lower", nat "Lower" 1 1 (fun ctx a ->
        let s = text_arg ctx "Lower" a.(0) in
        pay ctx s;
        Runtime.reserve ctx ((String.length s / 8) + 1);
        Text (String.lowercase_ascii s));
    on_text "Number" number;
    test2 "StartsWith" (fun prefix s -> String.starts_with ~prefix s);
    on_text "IsUtf8" (fun s -> Value.of_bool (is_utf8 s));
    "Count", nat "Count" 2 2 (fun ctx a ->
        let part = non_empty ctx "Count" (text_arg ctx "Count" a.(0)) and s = text_arg ctx "Count" a.(1) in
        pay ctx s;
        Int (count part s));
    test2 "Contains" (fun part s -> part = "" || find_from s part 0 >= 0) ]

(* The dictionary literal, which only the parser writes: the one name the compiler finds without a use. *)
let core = [ "#dict", nat "dict literal" 0 max_int dict_literal ]

let packages =
  [ "io", [ "Print", nat "Print" 0 max_int print; "PrintError", nat "PrintError" 0 max_int print_error ];
    "bug",
    [ "Panic", nat "Panic" 1 1 (fun ctx a -> Runtime.fail ctx User (Messages.plain (Value.text_of ctx a.(0))));
      "Assert", nat "Assert" 1 2 (fun ctx a ->
          match a.(0) with
          | True -> Missing
          | False ->
            let m =
              if Array.length a > 1 then Messages.plain (Value.text_of ctx a.(1)) else Messages.assertion
            in
            Runtime.fail ctx User m
          | v -> Runtime.fail ctx Type (Messages.condition (Value.describe v))) ];
    "text", text_natives @ [ "Str", nat "Str" 0 max_int str ];
    (* The current folder, for path.Abs, which tells where a path is: as Exists, the read permission on it. Once another
       process removed that folder, an absolute path needs none, as Filename and path.IsAbsolute agree, and a relative one
       is a bug of the kind io. *)
    "path", [ "windows", Value.of_bool Sys.win32;
              "here", nat "here" 1 1 (fun ctx a ->
                  let p = text_arg ctx "Abs" a.(0) in
                  Runtime.check_perm ctx Read (Some p);
                  match Sys.getcwd () with
                  | here -> Text here
                  | exception Sys_error _ when not (Filename.is_relative p) -> Text ""
                  | exception Sys_error _ -> Runtime.fail ctx Io (Messages.cwd_gone "path.Abs")) ];
    "dict",
    [ "Dict", nat "Dict" 0 1 dict_of_pairs;
      "Get", nat "Get" 2 2 (fun ctx a -> Option.fold ~none:Missing ~some:Value.share (Dict.get ctx "Get" a.(0) a.(1)));
      "GetOr", nat "GetOr" 3 3 (fun ctx a ->
          match Dict.get ctx "GetOr" a.(0) a.(2) with
          | Some x -> Value.share x
          | None -> a.(1));
      "Has", nat "Has" 2 2 (fun ctx a -> Value.of_bool (Option.is_some (Dict.get ctx "Has" a.(0) a.(1))));
      "Put", nat "Put" 3 3 (fun ctx a -> Dict.put ctx "Put" a.(0) (Value.share a.(1)) a.(2));
      "Drop", nat "Drop" 2 2 (fun ctx a -> Dict.drop ctx "Drop" a.(0) a.(1));
      "Keys", nat "Keys" 1 1 (fun ctx a -> dict_items ctx "Keys" a.(0) (fun k _ -> k));
      "Values", nat "Values" 1 1 (fun ctx a -> dict_items ctx "Values" a.(0) (fun _ v -> Value.share v));
      "Pairs", nat "Pairs" 1 1 (fun ctx a ->
          dict_items ctx "Pairs" a.(0) (fun k v -> Trie.record pair_keys [| k; Value.share v |]));
      "Fields", nat "Fields" 1 1 (fun ctx a ->
          match a.(0) with
          | Struct { shape = { sname = Some _; _ } as shape; fields = s; _ } ->
            let fields = Trie.vals_array s in
            (* Inside the package of the struct, its small fields too. *)
            let site = if ctx.site >= 0 && ctx.site < Vec.length ctx.w.sites then (Vec.get ctx.w.sites ctx.site).sver else None in
            let inside = (match site with Some v -> ctx.w.modules.(v.owner.pm).host = shape.sm | None -> false) in
            let keep = List.filter (fun i -> inside || Lexer.is_public shape.names.(i)) (List.init (Array.length fields) Fun.id) in
            Dict.of_items ctx (Array.of_list (List.concat_map (fun i -> [ Text shape.names.(i); Value.share fields.(i) ]) keep))
          | v -> Runtime.fail ctx Type (Messages.fields_of (Value.describe v))) ];
    "value",
    [ "Text", nat ~params:[| "x"; "most" |] "Text" 1 2 text;
      is_ "IsDict" (function Dict _ -> true | _ -> false);
      "Equal", nat "Equal" 2 2 (fun ctx a -> Value.of_bool (Value.equal ctx a.(0) a.(1)));
      "Size", nat ~params:[| "x"; "dim" |] "Size" 1 2 size;
      is_ "IsInt" (function Int _ -> true | _ -> false);
      is_ "IsFloat" (function Float _ -> true | _ -> false);
      is_ "IsNumber" (function Int _ | Float _ -> true | _ -> false);
      is_ "IsBool" (function True | False -> true | _ -> false);
      is_ "IsText" (function Text _ -> true | _ -> false);
      is_ "IsArray" (function Array _ -> true | _ -> false);
      is_ "IsStruct" (function Struct { shape = { sname = Some _; _ }; _ } -> true | _ -> false);
      is_ "IsFunction" (function Fun _ | Native _ -> true | _ -> false);
      is_ "IsMissing" (function Missing -> true | _ -> false) ];
    "math",
    [ "Div", int_native "Div" Arith.int_div;
      "Mod", int_native "Mod" Arith.int_mod;
      "Abs", nat ~ret:same_number "Abs" 1 1 (fun ctx a -> abs_value ctx a.(0));
      math1 "Sqrt" sqrt Kernels.Sqrt; math1 "Exp" exp Kernels.Exp; math1 "Log" log Kernels.Log; math1 "Sin" sin Kernels.Sin;
      math1 "Cos" cos Kernels.Cos; math1 "Tan" tan Kernels.Tan; math1 "Asin" asin Kernels.Asin;
      math1 "Acos" acos Kernels.Acos; math1 "Atan" atan Kernels.Atan; math1 "Log10" log10 Kernels.Log10;
      math1 "Log2" Float.log2 Kernels.Log2; math1 "Log1p" log1p Kernels.Log1p; math1 "Expm1" expm1 Kernels.Expm1;
      math1 "Cbrt" Kernels.cbrt Kernels.Cbrt; math1 "Sinh" sinh Kernels.Sinh; math1 "Cosh" cosh Kernels.Cosh;
      math1 "Tanh" tanh Kernels.Tanh; math1 "Asinh" Float.asinh Kernels.Asinh; math1 "Acosh" Float.acosh Kernels.Acosh;
      math1 "Atanh" Float.atanh Kernels.Atanh; math1 "SinDegrees" Kernels.sind Kernels.Sind;
      math1 "CosDegrees" Kernels.cosd Kernels.Cosd; math1 "TanDegrees" Kernels.tand Kernels.Tand;
      math1 "Epsilon" Kernels.spacing Kernels.Spacing;
      "Hypot", nat ~ret:(function [| (TI | TF); (TI | TF) |] -> TF | _ -> TA) "Hypot" 2 2 (fun ctx a -> Arith.hypot ctx a.(0) a.(1));
      "Clamp", nat ~params:[| "lo"; "hi"; "x" |] ~ret:(function [| _; _; TFA |] -> TFA | _ -> TA) "Clamp" 3 3 clamp;
      "Step", nat ~params:[| "x"; "zero" |] ~ret:(function [| TFA |] | [| TFA; _ |] -> TFA | [| TI | TF |] | [| (TI | TF); _ |] -> TF | _ -> TA) "Step" 1 2 step;
      "NextAfter", nat ~ret:(function [| (TI | TF); (TI | TF) |] -> TF | _ -> TA) "NextAfter" 2 2 (fun ctx a ->
          Arith.broadcast ctx (fun ctx x toward ->
              match x, toward with
              | Missing, _ | _, Missing -> Missing
              | _ ->
                let x = float_arg ctx "NextAfter" x and t = float_arg ctx "NextAfter" toward in
                Float (if Float.is_nan x || Float.is_nan t then nan else if t > x then Float.succ x else if t < x then Float.pred x else t))
            a.(0) a.(1));
      rounding "Floor" floor; rounding "Ceil" ceil; rounding "Round" Float.round;
      "Sign", nat ~ret:same_number "Sign" 1 1 (fun ctx a -> sign ctx a.(0));
      "Atan2", nat "Atan2" 2 2 (fun ctx a ->
          Arith.broadcast ctx (fun ctx y x ->
              match y, x with
              | Missing, _ | _, Missing -> Missing
              | _ ->
                let num v = match v with
                  | Int i -> float_of_int i
                  | Float f -> f
                  | _ -> Runtime.fail ctx Type (Messages.need_number "Atan2" (Value.describe v))
                in
                Float (Float.atan2 (num y) (num x))) a.(0) a.(1));
      "LogSumExp", nat ~params:[| "a"; "b" |] ~ret:(function [| TFA |] | [| (TI | TF); (TI | TF) |] -> TF | _ -> TA) "LogSumExp" 1 2 log_sum_exp;
      "Pi", Float Float.pi;
      "E", Float 2.718281828459045;
      "Nan", Float nan;
      "Inf", Float infinity;
      "MaxFloat", Float Float.max_float;
      "MinFloat", Float Float.min_float;
      "MaxInt", Int max_int;
      "MinInt", Int min_int ];
    "num", [ "ReplaceNan", nat ~params:[| "by"; "xs" |] ~ret:(function [| _; TFA |] -> TFA | _ -> TA) "ReplaceNan" 2 2 replace_nan;
             "dot", nat "dot" 2 2 dot; "luFactor", nat "luFactor" 1 1 lu_factor; "luSolve", nat "luSolve" 3 3 lu_solve ];
    "optimize",
    [ "direction", nat ~ret:fa_size "direction" 7 7 lbfgs_direction;
      "dot", nat ~ret:(fun _ -> TF) "dot" 2 2 dot_floats;
      "largest", nat ~ret:(fun _ -> TF) "largest" 1 1 largest ];
    "sparse",
    [ "ordering", nat "ordering" 3 3 sparse_ordering; "luFactor", nat "luFactor" 6 6 sparse_lu;
      "cholesky", nat "cholesky" 5 5 sparse_cholesky; "luFront", nat "luFront" 6 6 sparse_front ];
    "matrix",
    [ "Zeros", nat ~ret:fa_size "Zeros" 1 max_dims (fun ctx a -> filled ctx (Float 0.) (sizes_of ctx "Zeros" a 0));
      "Ones", nat ~ret:fa_size "Ones" 1 max_dims (fun ctx a -> filled ctx (Float 1.) (sizes_of ctx "Ones" a 0));
      "Reshape", nat "Reshape" 2 2 reshape;
      "Matmul", nat ~ret:fa_size "Matmul" 2 2 matmul;
      "Transpose", nat ~ret:same_fa "Transpose" 1 1 transpose ];
    "list",
    [ "merge", nat "merge" 2 2 (fun ctx a ->
          let o = Dict.items ctx "merge" a.(1) in
          (* A new map: a change copies, so the first one stays as it was. *)
          let acc = ref a.(0) in
          for i = 0 to (Array.length o / 2) - 1 do
            acc := Dict.put ctx "merge" o.(2 * i) (Value.share o.((2 * i) + 1)) !acc
          done;
          !acc);
      "Fill", nat "Fill" 2 (max_dims + 1) (fun ctx a -> filled ctx a.(0) (sizes_of ctx "Fill" a 1));
      "Sum", nat ~params:[| "xs"; "dim" |] ~ret:scalar_of_fa "Sum" 1 2 sum_of;
      "Mean", nat ~params:[| "xs"; "dim" |] ~ret:scalar_of_fa "Mean" 1 2 mean_of;
      "Min", nat ~ret:scalar_of_fa "Min" 1 2 (best "Min" Arith.lt (fun (x : float) y -> x < y));
      "Max", nat ~ret:scalar_of_fa "Max" 1 2 (best "Max" Arith.gt (fun (x : float) y -> x > y));
      "Any", nat "Any" 1 1 (mask_all "Any" true);
      "All", nat "All" 1 1 (mask_all "All" false) ] ]
