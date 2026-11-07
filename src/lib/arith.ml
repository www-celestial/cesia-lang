open Types

let text_involved a b = match a, b with Text _, _ | _, Text _ -> true | _ -> false

let bad ctx verb joiner flipped a b =
  let x, y = if flipped then b, a else a, b in
  Runtime.fail ctx Type (Messages.binary verb (Value.describe x) joiner (Value.describe y) (text_involved a b))

let[@inline] add_int ctx x y =
  let s = x + y in
  if (x lxor s) land (y lxor s) < 0
  then Runtime.fail ctx Math (Messages.overflow (string_of_int x) "+" (string_of_int y))
  else s

let[@inline] sub_int ctx x y =
  let s = x - y in
  if (x lxor y) land (x lxor s) < 0
  then Runtime.fail ctx Math (Messages.overflow (string_of_int x) "-" (string_of_int y))
  else s

let mul_overflow ctx x y =
  Runtime.fail ctx Math (Messages.overflow (string_of_int x) "*" (string_of_int y))

let small = 1 lsl 31

let[@inline] mul_int ctx x y =
  if abs x < small && abs y < small && x <> min_int && y <> min_int then x * y
  else if x = 0 || y = 0 then 0
  else begin
    let p = x * y in
    if (x = -1 && y = min_int) || (y = -1 && x = min_int) || p / y <> x then mul_overflow ctx x y else p
  end

(* A numeric operand: booleans count as 1 and 0. *)
let[@inline] as_num v = match v with True -> Int 1 | False -> Int 0 | _ -> v

(* Element by element, with a scalar or an array of the same shape. *)
let broadcast ctx scalar a b =
  let size r c = Runtime.build ctx (r * c) in
  match a, b with
  | Array x, Array y ->
    if not (Value.same_shape x y) then Runtime.fail ctx Type (Messages.shape (Arrays.sizes x) (Arrays.sizes y));
    size x.rows x.cols;
    Arrays.vals_like x (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k) (Value.elt y k)))
  | Array x, _ ->
    size x.rows x.cols;
    Arrays.vals_like x (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k) b))
  | _, Array y ->
    size y.rows y.cols;
    Arrays.vals_like y (Array.init (y.rows * y.cols) (fun k -> scalar ctx a (Value.elt y k)))
  | _ -> scalar ctx a b

let trim v = match v with Array x -> ignore (Value.trim x) | _ -> ()

let no_shape = { rows = 0; cols = 0; store = V [||]; a_owned = false; a_tip = false; dims = Arrays.flat }

(* The array whose shape an operation between typed stores, or a typed store and a number, takes; one of 0 cells for
   anything else, which goes cell by cell as before. *)
let typed a b =
  match a, b with
  | Array ({ store = I _ | F _; _ } as x), Array ({ store = I _ | F _; _ } as y) when Value.same_shape x y -> x
  | Array ({ store = I _ | F _; _ } as x), (Int _ | Float _) | (Int _ | Float _), Array ({ store = I _ | F _; _ } as x) -> x
  | _ -> no_shape

let int_cells = function Array { store = I d; _ } -> Some (d, 1) | Int i -> Some ([| i |], 0) | _ -> None

let scalar = function Int i -> float_of_int i | Float x -> x | _ -> nan

let float_cells = function
  | Array { store = F d; _ } -> d, 1
  | Array { store = I d; _ } -> Kernels.of_ints d, 1
  | v -> Float.Array.make 1 (scalar v), 0

(* A kernel saw an overflow: the cell by cell rule meets the first one and raises its error. *)
let overflow ctx op a b n =
  let int_op = match op with Kernels.Add -> add_int | Sub -> sub_int | _ -> mul_int in
  let cell v k = match v with Array { store = I d; _ } -> d.(k) | Int i -> i | _ -> 0 in
  for k = 0 to n - 1 do ignore (int_op ctx (cell a k) (cell b k)) done

(* Integers with their checks, floats, or integers made floats then as floats. Empty arrays and any other operand take
   the cell by cell path, as before. *)
let[@inline never] typed_fast ctx (op : Kernels.op) a b =
  let sh = typed a b in
  let n = sh.rows * sh.cols in
  if n = 0 then None
  else begin
    Runtime.build ctx n;
    match op, int_cells a, int_cells b with
    | (Add | Sub | Mul), Some x, Some y ->
      (match Kernels.ints op x y n with
       | Some d -> Some (Arrays.like sh (I d))
       | None ->
         overflow ctx op a b n;
         None)
    | _ ->
      Some
        (Arrays.like sh
           (F (match a, b with
               | Array { store = I x; _ }, (Int _ | Float _) -> Kernels.right_ints op x (scalar b)
               | (Int _ | Float _), Array { store = I y; _ } -> Kernels.left_ints op (scalar a) y
               | _ -> Kernels.both op (fst (float_cells a)) (fst (float_cells b)))))
  end

(* The fast path on F and I storage. *)
let fast ctx op a b =
  let result sh kernel =
    Runtime.build ctx (sh.rows * sh.cols);
    Some (Arrays.like sh (F (kernel ())))
  in
  (match a with Array x -> ignore (Value.trim x) | _ -> ());
  (match b with Array y -> ignore (Value.trim y) | _ -> ());
  match a, b with
  | Array ({ store = F x; _ } as sh), Array ({ store = F y; _ } as sy) when Value.same_shape sh sy ->
    result sh (fun () -> Kernels.both op x y)
  | Array ({ store = F x; _ } as sh), Float s -> result sh (fun () -> Kernels.right op x s)
  | Array ({ store = F x; _ } as sh), Int s -> result sh (fun () -> Kernels.right op x (float_of_int s))
  | Float s, Array ({ store = F y; _ } as sh) -> result sh (fun () -> Kernels.left op s y)
  | Int s, Array ({ store = F y; _ } as sh) -> result sh (fun () -> Kernels.left op (float_of_int s) y)
  | _ -> typed_fast ctx op a b

let numeric int_op float_op verb joiner flipped ctx a b =
  match as_num a, as_num b with
  | Int x, Int y -> Int (int_op ctx x y)
  | Float x, Float y -> Float (float_op x y)
  | Int x, Float y -> Float (float_op (float_of_int x) y)
  | Float x, Int y -> Float (float_op x (float_of_int y))
  | Missing, (Int _ | Float _ | Missing) | (Int _ | Float _), Missing -> Missing
  | _ -> bad ctx verb joiner flipped a b

let lifted op scalar ctx a b =
  match a, b with
  | Array _, _ | _, Array _ ->
    (match fast ctx op a b with
     | Some r -> r
     | None -> broadcast ctx scalar a b)
  | _ -> scalar ctx a b

let add_scalar ctx a b = numeric add_int ( +. ) "add" "and" false ctx a b
let sub_scalar ctx a b = numeric sub_int ( -. ) "subtract" "from" true ctx a b
let mul_scalar ctx a b = numeric mul_int ( *. ) "multiply" "by" false ctx a b
let add ctx a b = lifted Kernels.Add add_scalar ctx a b
let sub ctx a b = lifted Kernels.Sub sub_scalar ctx a b
let mul ctx a b = lifted Kernels.Mul mul_scalar ctx a b

let to_float v =
  match v with
  | Int x -> Some (float_of_int x)
  | Float x -> Some x
  | True -> Some 1.
  | False -> Some 0.
  | _ -> None

let div_scalar ctx a b =
  match to_float a, to_float b with
  | Some x, Some y -> Float (x /. y)
  | _ ->
    match a, b with
    | Missing, (Int _ | Float _ | True | False | Missing) | (Int _ | Float _ | True | False), Missing -> Missing
    | _ -> bad ctx "divide" "by" false a b

let div ctx a b = lifted Kernels.Div div_scalar ctx a b

let rec int_pow ctx base n =
  if n = 0 then 1
  else if n = 1 then base
  else begin
    let half = int_pow ctx base (n / 2) in
    let sq = mul_int ctx half half in
    if n land 1 = 1 then mul_int ctx sq base else sq
  end

let pow_scalar ctx a b =
  match as_num a, as_num b with
  | Int x, Int y when y >= 0 -> Int (int_pow ctx x y)
  | Missing, (Int _ | Float _ | Missing) | (Int _ | Float _), Missing -> Missing
  | x, y ->
    match to_float x, to_float y with
    | Some p, Some q -> Float (p ** q)
    | _ -> bad ctx "raise" "to the power" false a b

let pow ctx a b = broadcast ctx pow_scalar a b

let rec neg ctx a =
  match as_num a with
  | Array x ->
    Runtime.build ctx (x.rows * x.cols);
    Arrays.vals_like x (Array.init (x.rows * x.cols) (fun k -> neg ctx (Value.elt x k)))
  | Int x when x = min_int -> Runtime.fail ctx Math (Messages.overflow_neg (string_of_int x))
  | Int x -> Int (-x)
  | Float x -> Float (-.x)
  | Missing -> Missing
  | _ -> Runtime.fail ctx Type (Messages.negate (Value.describe a))

let order int_cmp float_cmp sym ctx a b =
  match a, b with
  | Int x, Int y -> Value.of_bool (int_cmp x y)
  | Float x, Float y -> Value.of_bool (float_cmp x y)
  | Int x, Float y -> Value.of_bool (float_cmp (float_of_int x) y)
  | Float x, Int y -> Value.of_bool (float_cmp x (float_of_int y))
  | Text x, Text y -> Value.of_bool (int_cmp (String.compare x y) 0)
  | Missing, (Int _ | Float _ | Missing) | (Int _ | Float _), Missing -> Missing
  | _ -> Runtime.fail ctx Type (Messages.compare_op (Value.describe a) sym (Value.describe b))

(* A comparison of typed stores, or of a typed store and a number, in one loop: a mask of booleans. [None] for anything
   else, which goes cell by cell as before. *)
let[@inline never] compared test ctx a b =
  trim a;
  trim b;
  let sh = typed a b in
  let n = sh.rows * sh.cols in
  if n = 0 then None
  else begin
    Runtime.build ctx n;
    let out = Array.make n False in
    (match int_cells a, int_cells b with
     | Some x, Some y -> Kernels.mask_ints test x y out
     | _ -> Kernels.mask_floats test (float_cells a) (float_cells b) out);
    Some (Arrays.vals_like sh out)
  end

let large = function Array x -> x.rows * x.cols >= 16 | _ -> false

(* Scalars and arrays of fewer than 16 cells go cell by cell, as before: a mask of a few cells costs less so. [swap]:
   the mask compares b with a, so that [>] is [<] turned. *)
let[@inline] masked swap test cell ctx a b =
  match a, b with
  | Array _, _ | _, Array _ ->
    let m = if large a || large b then compared test ctx (if swap then b else a) (if swap then a else b) else None in
    (match m with Some m -> m | None -> broadcast ctx cell a b)
  | _ -> cell ctx a b

let lt ctx a b = masked false Lt (order (fun (x : int) y -> x < y) (fun (x : float) y -> x < y) "<") ctx a b
let le ctx a b = masked false Le (order (fun (x : int) y -> x <= y) (fun (x : float) y -> x <= y) "<=") ctx a b
let gt ctx a b = masked true Lt (order (fun (x : int) y -> x > y) (fun (x : float) y -> x > y) ">") ctx a b
let ge ctx a b = masked true Le (order (fun (x : int) y -> x >= y) (fun (x : float) y -> x >= y) ">=") ctx a b

let same ctx a b =
  match a, b with
  | Float x, Float y -> x = y
  | _ -> Value.equal ctx a b

let eq ctx a b = masked false Eq (fun ctx x y -> Value.of_bool (same ctx x y)) ctx a b
let ne ctx a b = masked false Ne (fun ctx x y -> Value.of_bool (not (same ctx x y))) ctx a b

(* div and mod round down. *)
let int_div ctx a b =
  if b = 0 then Runtime.fail ctx Math (Messages.div_zero "Div")
  else if a = min_int && b = -1 then Runtime.fail ctx Math (Messages.overflow (string_of_int a) "/" "-1")
  else begin
    let q = a / b in
    if a mod b <> 0 && a < 0 <> (b < 0) then q - 1 else q
  end

let int_mod ctx a b =
  if b = 0 then Runtime.fail ctx Math (Messages.div_zero "Mod")
  else begin
    let r = a mod b in
    if r <> 0 && r < 0 <> (b < 0) then r + b else r
  end
