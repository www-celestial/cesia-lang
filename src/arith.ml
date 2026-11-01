open Types

let text_involved a b = match a, b with Text _, _ | _, Text _ -> true | _ -> false

let bad ctx verb joiner flipped a b =
  let x, y = if flipped then b, a else a, b in
  Runtime.fail ctx Type (Messages.binary verb (Value.describe x) joiner (Value.describe y) (text_involved a b))

let[@inline] add_int ctx x y =
  let s = x + y in
  if (x lxor s) land (y lxor s) < 0
  then Runtime.fail ctx Overflow (Messages.overflow (string_of_int x) "+" (string_of_int y))
  else s

let[@inline] sub_int ctx x y =
  let s = x - y in
  if (x lxor y) land (x lxor s) < 0
  then Runtime.fail ctx Overflow (Messages.overflow (string_of_int x) "-" (string_of_int y))
  else s

let mul_overflow ctx x y =
  Runtime.fail ctx Overflow (Messages.overflow (string_of_int x) "*" (string_of_int y))

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
    if x.rows <> y.rows || x.cols <> y.cols then
      Runtime.fail ctx Type (Messages.shape x.rows x.cols y.rows y.cols);
    size x.rows x.cols;
    Arrays.of_vals x.rows x.cols
      (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k) (Value.elt y k)))
  | Array x, _ ->
    size x.rows x.cols;
    Arrays.of_vals x.rows x.cols (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k) b))
  | _, Array y ->
    size y.rows y.cols;
    Arrays.of_vals y.rows y.cols (Array.init (y.rows * y.cols) (fun k -> scalar ctx a (Value.elt y k)))
  | _ -> scalar ctx a b

(* The fast path on F storage. *)
let fast ctx op a b =
  let result rows cols kernel =
    Runtime.build ctx (rows * cols);
    Some (Arrays.of_float rows cols (kernel ()))
  in
  match a, b with
  | Array { rows; cols; store = F x; _ }, Array { rows = r; cols = c; store = F y; _ } when rows = r && cols = c ->
    result rows cols (fun () -> Kernels.both op x y)
  | Array { rows; cols; store = F x; _ }, Float s -> result rows cols (fun () -> Kernels.right op x s)
  | Array { rows; cols; store = F x; _ }, Int s ->
    result rows cols (fun () -> Kernels.right op x (float_of_int s))
  | Float s, Array { rows; cols; store = F y; _ } -> result rows cols (fun () -> Kernels.left op s y)
  | Int s, Array { rows; cols; store = F y; _ } ->
    result rows cols (fun () -> Kernels.left op (float_of_int s) y)
  | _ -> None

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
    Arrays.of_vals x.rows x.cols (Array.init (x.rows * x.cols) (fun k -> neg ctx (Value.elt x k)))
  | Int x when x = min_int -> Runtime.fail ctx Overflow (Messages.overflow_neg (string_of_int x))
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

let lt ctx a b = broadcast ctx (order (fun (x : int) y -> x < y) (fun (x : float) y -> x < y) "<") a b
let le ctx a b = broadcast ctx (order (fun (x : int) y -> x <= y) (fun (x : float) y -> x <= y) "<=") a b
let gt ctx a b = broadcast ctx (order (fun (x : int) y -> x > y) (fun (x : float) y -> x > y) ">") a b
let ge ctx a b = broadcast ctx (order (fun (x : int) y -> x >= y) (fun (x : float) y -> x >= y) ">=") a b

let same ctx a b =
  match a, b with
  | Float x, Float y -> x = y
  | _ -> Value.equal ctx a b

let eq ctx a b = broadcast ctx (fun ctx x y -> Value.of_bool (same ctx x y)) a b
let ne ctx a b = broadcast ctx (fun ctx x y -> Value.of_bool (not (same ctx x y))) a b

(* div and mod round down. *)
let int_div ctx a b =
  if b = 0 then Runtime.fail ctx Overflow (Messages.div_zero "div")
  else if a = min_int && b = -1 then Runtime.fail ctx Overflow (Messages.overflow (string_of_int a) "/" "-1")
  else begin
    let q = a / b in
    if a mod b <> 0 && a < 0 <> (b < 0) then q - 1 else q
  end

let int_mod ctx a b =
  if b = 0 then Runtime.fail ctx Overflow (Messages.div_zero "mod")
  else begin
    let r = a mod b in
    if r <> 0 && r < 0 <> (b < 0) then r + b else r
  end
