type op = Add | Sub | Mul | Div | Pow | Hypot

let both op x y =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i +. Float.Array.get y i) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i -. Float.Array.get y i) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i *. Float.Array.get y i) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i /. Float.Array.get y i) done
      | Pow -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i ** Float.Array.get y i) done
      | Hypot -> for i = lo to hi - 1 do Float.Array.set out i (Float.hypot (Float.Array.get x i) (Float.Array.get y i)) done);
  out

let right op x s =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i +. s) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i -. s) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i *. s) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i /. s) done
      | Pow -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i ** s) done
      | Hypot -> for i = lo to hi - 1 do Float.Array.set out i (Float.hypot (Float.Array.get x i) s) done);
  out

let left op s y =
  let n = Float.Array.length y in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (s +. Float.Array.get y i) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (s -. Float.Array.get y i) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (s *. Float.Array.get y i) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (s /. Float.Array.get y i) done
      | Pow -> for i = lo to hi - 1 do Float.Array.set out i (s ** Float.Array.get y i) done
      | Hypot -> for i = lo to hi - 1 do Float.Array.set out i (Float.hypot s (Float.Array.get y i)) done);
  out

(* Loops over I storage, with the checks of [Arith.add_int], [sub_int] and [mul_int]: [None] when a cell overflows, so
   that the caller finds it again and raises its error. An operand is a store and its step: a scalar is one cell read
   with a step of 0. *)
let small = 1 lsl 31

let[@inline] mul_fits x y =
  (abs x < small && abs y < small && x <> min_int && y <> min_int) || x = 0 || y = 0
  || not ((x = -1 && y = min_int) || (y = -1 && x = min_int) || (x * y) / y <> x)

let ints op ((x : int array), sx) ((y : int array), sy) n =
  let out = Array.make n 0 and ok = Atomic.make true in
  Par.ranges n (fun lo hi ->
      let bad = ref 0 in
      (match op with
       | Add ->
         for i = lo to hi - 1 do
           let a = x.(i * sx) and b = y.(i * sy) in
           let s = a + b in
           out.(i) <- s;
           bad := !bad lor ((a lxor s) land (b lxor s))
         done
       | Sub ->
         for i = lo to hi - 1 do
           let a = x.(i * sx) and b = y.(i * sy) in
           let s = a - b in
           out.(i) <- s;
           bad := !bad lor ((a lxor b) land (a lxor s))
         done
       | Mul ->
         for i = lo to hi - 1 do
           let a = x.(i * sx) and b = y.(i * sy) in
           if mul_fits a b then out.(i) <- a * b else bad := -1
         done
       | Div | Pow | Hypot -> bad := -1);
      if !bad < 0 then Atomic.set ok false);
  if Atomic.get ok then Some out else None

let of_ints d =
  let n = Array.length d in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi -> for i = lo to hi - 1 do Float.Array.set out i (float_of_int d.(i)) done);
  out

(* [right] and [left] on integers, each made a float on the way. *)
let right_ints op (x : int array) s =
  let n = Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (float_of_int x.(i) +. s) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (float_of_int x.(i) -. s) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (float_of_int x.(i) *. s) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (float_of_int x.(i) /. s) done
      | Pow -> for i = lo to hi - 1 do Float.Array.set out i (float_of_int x.(i) ** s) done
      | Hypot -> for i = lo to hi - 1 do Float.Array.set out i (Float.hypot (float_of_int x.(i)) s) done);
  out

let left_ints op s (y : int array) =
  let n = Array.length y in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (s +. float_of_int y.(i)) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (s -. float_of_int y.(i)) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (s *. float_of_int y.(i)) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (s /. float_of_int y.(i)) done
      | Pow -> for i = lo to hi - 1 do Float.Array.set out i (s ** float_of_int y.(i)) done
      | Hypot -> for i = lo to hi - 1 do Float.Array.set out i (Float.hypot s (float_of_int y.(i))) done);
  out

(* Masks: [true] or [false] in [out] for each pair of cells; [x > y] is [y < x]. Comparisons of floats follow IEEE, so
   NaN is equal to nothing. *)
type test = Lt | Le | Eq | Ne

let[@inline] truth b : Types.t = if b then True else False

let mask_ints test ((x : int array), sx) ((y : int array), sy) (out : Types.t array) =
  Par.ranges (Array.length out) (fun lo hi ->
      match test with
      | Lt -> for i = lo to hi - 1 do out.(i) <- truth (x.(i * sx) < y.(i * sy)) done
      | Le -> for i = lo to hi - 1 do out.(i) <- truth (x.(i * sx) <= y.(i * sy)) done
      | Eq -> for i = lo to hi - 1 do out.(i) <- truth (x.(i * sx) = y.(i * sy)) done
      | Ne -> for i = lo to hi - 1 do out.(i) <- truth (x.(i * sx) <> y.(i * sy)) done)

let mask_floats test (x, sx) (y, sy) (out : Types.t array) =
  Par.ranges (Array.length out) (fun lo hi ->
      match test with
      | Lt -> for i = lo to hi - 1 do out.(i) <- truth (Float.Array.get x (i * sx) < Float.Array.get y (i * sy)) done
      | Le -> for i = lo to hi - 1 do out.(i) <- truth (Float.Array.get x (i * sx) <= Float.Array.get y (i * sy)) done
      | Eq -> for i = lo to hi - 1 do out.(i) <- truth (Float.Array.get x (i * sx) = Float.Array.get y (i * sy)) done
      | Ne -> for i = lo to hi - 1 do out.(i) <- truth (Float.Array.get x (i * sx) <> Float.Array.get y (i * sy)) done)

type fn = Neg | Abs | Sqrt | Exp | Log | Sin | Cos | Tan | Asin | Acos | Atan | Log10 | Log2 | Log1p | Expm1 | Cbrt | Sinh
  | Cosh | Tanh | Asinh | Acosh | Atanh | Sind | Cosd | Tand | Spacing

(* An angle in degrees: x = 90 q + r exactly, |r| <= 45, the reduction of Karney's sind (Algorithms for geodesics, J. Geodesy
   87, 2013), then sin or cos of r in radians, at 30 and 45 degrees their correctly rounded values. *)
let[@inline] sin_r r =
  let a = Float.abs r in
  if a = 45. then Float.copy_sign 0.7071067811865476 r else if a = 30. then Float.copy_sign 0.5 r else sin (r *. 0.017453292519943295)
let[@inline] cos_r r =
  let a = Float.abs r in
  if a = 45. then 0.7071067811865476 else if a = 30. then 0.8660254037844386 else cos (r *. 0.017453292519943295)

let sind x =
  let r = Float.rem x 360. in
  let q = Float.round (r /. 90.) in
  let r = r -. (90. *. q) in
  let s = match int_of_float q land 3 with 0 -> sin_r r | 1 -> cos_r r | 2 -> -.sin_r r | _ -> -.cos_r r in
  if s = 0. then Float.copy_sign 0. x else s

let cosd x =
  let r = Float.rem x 360. in
  let q = Float.round (r /. 90.) in
  let r = r -. (90. *. q) in
  (match int_of_float q land 3 with 0 -> cos_r r | 1 -> -.sin_r r | 2 -> -.cos_r r | _ -> sin_r r) +. 0.

(* tan and its inverse of r in degrees, |r| <= 45, one rounding of the C library's tan of r in radians but at 30 and 45. *)
let[@inline] tan_r r =
  let a = Float.abs r in
  if a = 45. then Float.copy_sign 1. r else if a = 30. then Float.copy_sign 0.5773502691896257 r else tan (r *. 0.017453292519943295)

let[@inline] cot_r r =
  let a = Float.abs r in
  if a = 45. then Float.copy_sign 1. r else if a = 30. then Float.copy_sign 1.7320508075688772 r else 1. /. tan (r *. 0.017453292519943295)

(* tan (90 q + r) is tan r for an even q, -cot r for an odd one; at a pole, the infinity of C23's tanpi: inf at 90 + 360 k,
   -inf at 270 + 360 k, and a zero its sign: -0 at an odd multiple of 180 above 0. *)
let tand x =
  let r = Float.rem x 360. in
  let q = Float.round (r /. 90.) in
  let r = r -. (90. *. q) and p = int_of_float q land 3 in
  if p land 1 = 1 then (if r = 0. then (if p = 1 then infinity else neg_infinity) else -.cot_r r)
  else
    let t = tan_r r in
    if t = 0. then Float.copy_sign 0. (if p = 2 then -.x else x) else t

let spacing x =
  let a = Float.abs x in
  if a = Float.max_float then a -. Float.pred a else Float.succ a -. a

(* The cube root, correctly rounded, where the C library's is up to 3 ulps away (glibc 2.44: cbrt 27 is
   3.0000000000000004). The sign of an exact sum of floats, by Shewchuk's Grow-Expansion (Adaptive precision
   floating-point arithmetic, 1997): each term added with no error to an expansion, whose last nonzero part has the sign
   of the sum. *)
let exact_sign (terms : float array) =
  let e = Array.make (Array.length terms) 0. and n = ref 0 in
  Array.iter
    (fun x ->
       let q = ref x in
       for i = 0 to !n - 1 do
         let a = !q and b = e.(i) in
         let s = a +. b in
         let bv = s -. a in
         e.(i) <- (a -. (s -. bv)) +. (b -. bv);
         q := s
       done;
       e.(!n) <- !q;
       incr n)
    terms;
  Array.fold_left (fun s x -> if x <> 0. then x else s) 0. e

(* Is (t + h)^3 above f? Each part of t^3 + 3 t^2 h + 3 t h^2 + h^3 - f exact, h half an ulp of t in [1, 2]. *)
let above t h f =
  let p = t *. t and h3 = 3. *. h and hh = h *. h in
  let pe = Float.fma t t (-.p) in
  let a = p *. t and b = pe *. t and c = h3 *. p and d = h3 *. pe and g = 3. *. t in
  exact_sign
    [| -.f; a; Float.fma p t (-.a); b; Float.fma pe t (-.b); c; Float.fma h3 p (-.c); d; Float.fma h3 pe (-.d);
       g *. hh; Float.fma 3. t (-.g) *. hh; hh *. h |]
  > 0.

(* The root of f in [1, 8) from y, within an ulp of it: Newton's step from the residual f - y^3 to 2^-104 of f, then,
   within 2^-30 of an ulp of a midpoint, the side of it that the exact sign gives. *)
let[@inline never] settle f y =
  let s = y *. y in
  let se = Float.fma y y (-.s) and c = s *. y in
  let d = (f -. c -. Float.fma s y (-.c) -. (se *. y)) /. (3. *. s) in
  let y1 = y +. d in
  let rem = y -. y1 +. d in
  let h = (if rem > 0. then Float.succ y1 -. y1 else Float.pred y1 -. y1) *. 0.5 in
  if Float.abs (Float.abs rem -. Float.abs h) > Float.abs h *. 0x1p-30 then y1
  else if above y1 h f = (h > 0.) then y1
  else y1 +. (2. *. h)

let thirds = Float.Array.of_list [ 1.; 1.2599210498948732; 1.5874010519681994 ]

(* |x| = f 2^(3 q), f = m 2^k in [1, 8), m in [1, 2). t: cbrt m to 2^-18, Chebyshev's polynomial of degree 5, times
   2^(k/3), rounded to 17 bits so that t^3 and f - t^3 are exact. With u = (f - t^3) / f, below 2^-14.8,
   cbrt f = t (1 - u)^(-1/3) = t (1 + u/3 + 2u^2/9 + 14u^3/81 + 35u^4/243 + ...), to 2^-66 of f: t + w rounds right but
   within 2^-63 of a midpoint, one time in a thousand, where [settle] decides. *)
let[@inline] cube_root x bits ex =
  let e = ex - 1023 in
  let q = if e >= 0 then e / 3 else -((2 - e) / 3) in
  let k = e - (3 * q) in
  let m = Int64.float_of_bits (Int64.logor (Int64.logand bits 0xfffffffffffffL) 0x3ff0000000000000L) in
  let f = if k = 0 then m else if k = 1 then m *. 2. else m *. 4. in
  let inv = 1. /. f and m2 = m *. m in
  let t =
    (0.47528789479229594 +. (m *. 0.8315701002007011) +. (m2 *. (-0.4604949010233348 +. (m *. 0.19708010287654082)))
     +. (m2 *. m2 *. (-0.048556589709651425 +. (m *. 0.005116866908752332))))
    *. Float.Array.get thirds k
  in
  let t = t +. 0x1.8p36 -. 0x1.8p36 in
  let u = (f -. (t *. t *. t)) *. inv in
  let w =
    t *. u *. (0.3333333333333333 +. (u *. 0.2222222222222222) +. (u *. u *. (0.1728395061728395 +. (u *. 0.1440329218106996))))
  in
  let y = t +. w in
  let a = Float.abs (t -. y +. w) in
  let y = if (Float.abs (a -. 0x1p-53) > 0x1p-63 && y > 1. && y < 2.) || a < 0x1p-56 then y else settle f y in
  let y = y *. Int64.float_of_bits (Int64.shift_left (Int64.of_int (q + 1023)) 52) in
  if x < 0. then -.y else y

(* A subnormal times 2^162, whose root is 2^54 times its own. *)
let[@inline never] subnormal_root x =
  let z = x *. 0x1p162 in
  let bits = Int64.bits_of_float z in
  cube_root z bits (Int64.to_int (Int64.shift_right_logical bits 52) land 0x7ff) *. 0x1p-54

let[@inline] cbrt x =
  let bits = Int64.bits_of_float x in
  let ex = Int64.to_int (Int64.shift_right_logical bits 52) land 0x7ff in
  if ex = 0x7ff || x = 0. then x else if ex = 0 then subnormal_root x else cube_root x bits ex

(* A loop per function, so that each float goes to it unboxed: through a closure, each was boxed on the way in and out. *)
let map fn x =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match fn with
      | Neg -> for i = lo to hi - 1 do Float.Array.set out i (Float.neg (Float.Array.get x i)) done
      | Abs -> for i = lo to hi - 1 do Float.Array.set out i (Float.abs (Float.Array.get x i)) done
      | Sqrt -> for i = lo to hi - 1 do Float.Array.set out i (sqrt (Float.Array.get x i)) done
      | Exp -> for i = lo to hi - 1 do Float.Array.set out i (exp (Float.Array.get x i)) done
      | Log -> for i = lo to hi - 1 do Float.Array.set out i (log (Float.Array.get x i)) done
      | Sin -> for i = lo to hi - 1 do Float.Array.set out i (sin (Float.Array.get x i)) done
      | Cos -> for i = lo to hi - 1 do Float.Array.set out i (cos (Float.Array.get x i)) done
      | Tan -> for i = lo to hi - 1 do Float.Array.set out i (tan (Float.Array.get x i)) done
      | Asin -> for i = lo to hi - 1 do Float.Array.set out i (asin (Float.Array.get x i)) done
      | Acos -> for i = lo to hi - 1 do Float.Array.set out i (acos (Float.Array.get x i)) done
      | Atan -> for i = lo to hi - 1 do Float.Array.set out i (atan (Float.Array.get x i)) done
      | Log10 -> for i = lo to hi - 1 do Float.Array.set out i (log10 (Float.Array.get x i)) done
      | Log2 -> for i = lo to hi - 1 do Float.Array.set out i (Float.log2 (Float.Array.get x i)) done
      | Log1p -> for i = lo to hi - 1 do Float.Array.set out i (log1p (Float.Array.get x i)) done
      | Expm1 -> for i = lo to hi - 1 do Float.Array.set out i (expm1 (Float.Array.get x i)) done
      | Cbrt -> for i = lo to hi - 1 do Float.Array.set out i (cbrt (Float.Array.get x i)) done
      | Sinh -> for i = lo to hi - 1 do Float.Array.set out i (sinh (Float.Array.get x i)) done
      | Cosh -> for i = lo to hi - 1 do Float.Array.set out i (cosh (Float.Array.get x i)) done
      | Tanh -> for i = lo to hi - 1 do Float.Array.set out i (tanh (Float.Array.get x i)) done
      | Asinh -> for i = lo to hi - 1 do Float.Array.set out i (Float.asinh (Float.Array.get x i)) done
      | Acosh -> for i = lo to hi - 1 do Float.Array.set out i (Float.acosh (Float.Array.get x i)) done
      | Atanh -> for i = lo to hi - 1 do Float.Array.set out i (Float.atanh (Float.Array.get x i)) done
      | Sind -> for i = lo to hi - 1 do Float.Array.set out i (sind (Float.Array.get x i)) done
      | Cosd -> for i = lo to hi - 1 do Float.Array.set out i (cosd (Float.Array.get x i)) done
      | Tand -> for i = lo to hi - 1 do Float.Array.set out i (tand (Float.Array.get x i)) done
      | Spacing -> for i = lo to hi - 1 do Float.Array.set out i (spacing (Float.Array.get x i)) done);
  out

(* log(exp x + exp y), numpy's logaddexp: the larger plus log1p of exp of the difference; ln 2 more for equals, so that
   infinities of one sign give themselves. *)
let log_add_exp x y =
  if x = y then x +. 0.6931471805599453
  else
    let d = x -. y in
    if d > 0. then x +. log1p (exp (-.d)) else if d <= 0. then y +. log1p (exp d) else d

(* log(sum(exp x)), after Blanchard, Higham and Higham (Accurately computing the log-sum-exp and softmax functions, IMA J.
   Numer. Anal. 41, 2021): the first largest cell m, then m + log1p of the sum of exp(x - m) of the others, which keeps
   the digits of small terms beside its 1; -inf for no cell, inf with an inf, NaN with a NaN. *)
let log_sum_exp x =
  let n = Float.Array.length x in
  let k = ref (-1) and m = ref neg_infinity and nan = ref false in
  for i = 0 to n - 1 do
    let v = Float.Array.get x i in
    if v > !m then begin m := v; k := i end else if Float.is_nan v then nan := true
  done;
  let m = !m and k = !k in
  if !nan then Float.nan
  else if k < 0 || m = infinity then m
  else begin
    let s = ref 0. in
    for i = 0 to n - 1 do if i <> k then s := !s +. exp (Float.Array.get x i -. m) done;
    m +. log1p !s
  end

type pick = Clamp of float * float | Nan of float | Step of float

let[@inline] one p v =
  match p with
  | Clamp (lo, hi) -> if v < lo then lo else if v > hi then hi else v
  | Nan by -> if Float.is_nan v then by else v
  | Step zero -> if v > 0. then 1. else if v < 0. then 0. else if v = 0. then zero else v

let pick p x =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun i j ->
      match p with
      | Clamp (lo, hi) -> for k = i to j - 1 do let v = Float.Array.get x k in Float.Array.set out k (if v < lo then lo else if v > hi then hi else v) done
      | Nan by -> for k = i to j - 1 do let v = Float.Array.get x k in Float.Array.set out k (if Float.is_nan v then by else v) done
      | Step _ -> for k = i to j - 1 do Float.Array.set out k (one p (Float.Array.get x k)) done);
  out

(* In blocks of a fixed size, so that the rounding doesn't depend on the number of cores. *)
let block = 1 lsl 16

let sum x =
  let n = Float.Array.length x in
  let blocks = (n + block - 1) / block in
  let totals = Float.Array.make blocks 0. in
  Par.ranges ~grain:2 blocks (fun lo hi ->
      for b = lo to hi - 1 do
        let acc = ref 0. in
        for i = b * block to min n ((b + 1) * block) - 1 do acc := !acc +. Float.Array.get x i done;
        Float.Array.set totals b !acc
      done);
  Float.Array.fold_left ( +. ) 0. totals

let dot x y =
  let n = Float.Array.length x in
  let blocks = (n + block - 1) / block in
  let totals = Float.Array.make blocks 0. in
  Par.ranges ~grain:2 blocks (fun lo hi ->
      for b = lo to hi - 1 do
        let acc = ref 0. in
        for i = b * block to min n ((b + 1) * block) - 1 do
          acc := !acc +. (Float.Array.get x i *. Float.Array.get y i)
        done;
        Float.Array.set totals b !acc
      done);
  Float.Array.fold_left ( +. ) 0. totals

(* For each cell of the result, from 0 to [inner * outer], the sum of the [len] cells of [x] at [inner] from each other,
   in order: a sum along a dimension, with [inner] cells before it and [outer] after. *)
let along ~inner ~len ~outer f =
  Par.ranges ~grain:(max 1 ((1 lsl 17) / max 1 len)) (inner * outer) (fun lo hi ->
      let c = ref (lo / inner) in
      while !c * inner < hi do
        let first = !c * inner in
        f ~dst:first ~src:(first * len) ~lo:(max lo first - first) ~hi:(min hi (first + inner) - first);
        incr c
      done)

let sum_along ~inner ~len ~outer x =
  let out = Float.Array.make (inner * outer) 0. in
  if inner > 0 then
    along ~inner ~len ~outer (fun ~dst ~src ~lo ~hi ->
        for b = 0 to len - 1 do
          let at = src + (b * inner) in
          for a = lo to hi - 1 do
            Float.Array.set out (dst + a) (Float.Array.get out (dst + a) +. Float.Array.get x (at + a))
          done
        done);
  out

let sum_along_ints ~inner ~len ~outer (x : int array) =
  let out = Array.make (inner * outer) 0 and ok = Atomic.make true in
  if inner > 0 then
    along ~inner ~len ~outer (fun ~dst ~src ~lo ~hi ->
        let bad = ref 0 in
        for b = 0 to len - 1 do
          let at = src + (b * inner) in
          for a = lo to hi - 1 do
            let p = out.(dst + a) and q = x.(at + a) in
            let s = p + q in
            out.(dst + a) <- s;
            bad := !bad lor ((p lxor s) land (q lxor s))
          done
        done;
        if !bad < 0 then Atomic.set ok false);
  if Atomic.get ok then Some out else None

type block = { data : floatarray; offset : int; ld : int }

let gemm = ref (fun ~rows:_ ~cols:_ ~inner:_ ~trans:_ ~sub:_ ~threads:_ _ _ _ -> false)

(* The grain of a loop over columns of this many cells each. *)
let column_grain cells = max 1 ((1 lsl 17) / max 1 cells)

(* By columns, to follow the storage order. Below 32^3 products, this loop is fast enough and gives the same bits on
   every machine; above, a library when the machine has one. *)
let matmul ~rows ~cols ~inner ~out x y =
  if
    rows > 0 && inner > 0
    && not
         (float rows *. float cols *. float inner >= 32768.
         && !gemm ~rows ~cols ~inner ~trans:false ~sub:false ~threads:0 { data = out; offset = 0; ld = rows }
              { data = x; offset = 0; ld = rows } { data = y; offset = 0; ld = inner })
  then
    Par.ranges ~grain:(column_grain (rows * inner)) cols (fun lo hi ->
        for j = lo to hi - 1 do
          let dst = j * rows in
          for k = 0 to inner - 1 do
            let b = Float.Array.get y ((j * inner) + k) in
            let src = k * rows in
            for i = 0 to rows - 1 do
              Float.Array.set out (dst + i) (Float.Array.get out (dst + i) +. (Float.Array.get x (src + i) *. b))
            done
          done
        done);
  out

let insertion a lo hi cmp =
  for i = lo + 1 to hi - 1 do
    let x = a.(i) in
    let j = ref (i - 1) in
    while !j >= lo && cmp a.(!j) x > 0 do
      a.(!j + 1) <- a.(!j);
      decr j
    done;
    a.(!j + 1) <- x
  done

(* Two sorted runs of [src], from lo to mid and from mid to hi, into [dst] from lo. *)
let merge src dst lo mid hi cmp =
  let i = ref lo and j = ref mid in
  for k = lo to hi - 1 do
    if !i < mid && (!j >= hi || cmp src.(!i) src.(!j) <= 0) then begin
      dst.(k) <- src.(!i);
      incr i
    end else begin
      dst.(k) <- src.(!j);
      incr j
    end
  done

let rec sort_range a b lo hi cmp =
  if hi - lo <= 16 then insertion a lo hi cmp
  else begin
    let mid = lo + ((hi - lo) / 2) in
    sort_range a b lo mid cmp;
    sort_range a b mid hi cmp;
    if cmp a.(mid - 1) a.(mid) > 0 then begin
      Array.blit a lo b lo (hi - lo);
      merge b a lo mid hi cmp
    end
  end

(* Sorts one run per core, then merges them two by two, from one array to the other. *)
let sort_parallel a b n cmp =
  let rec power k = if 2 * k > min (Par.cores ()) (n / (1 lsl 15)) then k else power (2 * k) in
  let runs = power 1 in
  let bound k = n * k / runs in
  Par.each runs (fun k -> sort_range a b (bound k) (bound (k + 1)) cmp);
  let rec merge_up src dst width =
    if width >= runs then src
    else begin
      Par.each (runs / (2 * width)) (fun k ->
          let lo = 2 * k * width in
          merge src dst (bound lo) (bound (lo + width)) (bound (lo + (2 * width))) cmp);
      merge_up dst src (2 * width)
    end
  in
  merge_up a b 1

let sort_positions ?(parallel = false) n cmp =
  let a = Array.init n Fun.id and b = Array.make n 0 in
  if parallel && n >= 1 lsl 17 && Par.cores () > 1 then sort_parallel a b n cmp
  else begin
    sort_range a b 0 n cmp;
    a
  end

let transpose ~rows ~cols x =
  let n = rows * cols in
  let out = Float.Array.create n in
  if n > 0 then
    Par.ranges ~grain:(column_grain rows) cols (fun lo hi ->
        for j = lo to hi - 1 do
          for i = 0 to rows - 1 do
            Float.Array.set out ((i * cols) + j) (Float.Array.get x ((j * rows) + i))
          done
        done);
  out
