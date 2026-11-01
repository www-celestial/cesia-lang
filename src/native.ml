open Types

(* A direct call doesn't share its arguments, so that measuring a variable leaves it owned. A native returning one of
   its inputs therefore creates the second reference here. *)
let nat ?perm ?(params = [||]) ?(ret = fun _ -> TA) nname min_args max_args run =
  let run ctx (a : t array) =
    let r = run ctx a in
    if Array.memq r a then Value.share r else r
  in
  Native { nname; perm; params; min_args; max_args; ret_ty = ret; run; f1 = None; i2 = None }

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
      f1 = None; i2 = Some f }

(* The return types inference can know. *)
let same_number (a : ty array) =
  match a with
  | [| TI |] -> TI
  | [| TF |] -> TF
  | [| TFA |] -> TFA
  | _ -> TA

let float_of_number (a : ty array) =
  match a with
  | [| (TI | TF) |] -> TF
  | [| TFA |] -> TFA
  | _ -> TA

let scalar_of_fa (a : ty array) =
  match a with
  | [| TFA |] -> TF
  | _ -> TA

let fa_size (_ : ty array) = TFA

let same_fa (a : ty array) =
  match a with
  | [| TFA |] -> TFA
  | _ -> TA

let print ctx args =
  let w = ctx.w in
  Array.iteri
    (fun i v ->
       if i > 0 then Buffer.add_char w.out ' ';
       Buffer.add_string w.out (Value.text_of ctx v))
    args;
  Buffer.add_char w.out '\n';
  if Buffer.length w.out > 65536 then Runtime.flush_out w;
  Missing

let code_points s =
  let n = ref 0 in
  String.iter (fun c -> if Char.code c land 0xC0 <> 0x80 then incr n) s;
  !n

let length v =
  match v with
  | Text s -> code_points s
  | Array a -> a.rows * a.cols
  | Struct r -> Array.length r.fields
  | _ -> 1

let dim ctx name v =
  match v with
  | Int i when i >= 0 -> i
  | Float x when Float.is_integer x && x >= 0. && x < 4e18 -> int_of_float x
  | _ -> Runtime.fail ctx Type (Messages.bad_size name (Value.describe v))

(* n, or rows and columns, starting at argument [at]. *)
let dims ctx name (a : t array) at =
  if Array.length a > at + 1 then dim ctx name a.(at), dim ctx name a.(at + 1) else 1, dim ctx name a.(at)

let filled ctx value rows cols =
  let n = Runtime.cells ctx rows cols in
  Runtime.charge ctx ((n / 16) + 1);
  match value with
  | Float x -> Arrays.of_float rows cols (Runtime.alloc_float ctx n x)
  | v -> Array { rows; cols; store = V (Runtime.alloc_vals ctx n (Value.share v)); a_owned = true }

let size ctx (a : t array) =
  let rows, cols = match a.(0) with Array x -> x.rows, x.cols | _ -> 1, 1 in
  if Array.length a = 1 then Array { rows = 1; cols = 2; store = V [| Int rows; Int cols |]; a_owned = true }
  else
    match a.(1) with
    | Int 1 -> Int rows
    | Int 2 -> Int cols
    | v -> Runtime.fail ctx Index (Messages.size_dim (Value.describe v))

let reshape ctx (a : t array) =
  let rows = dim ctx "reshape" a.(1) and cols = dim ctx "reshape" a.(2) in
  match a.(0) with
  | Array x ->
    let n = x.rows * x.cols in
    if Runtime.cells ctx rows cols <> n then Runtime.fail ctx Type (Messages.reshape_size n rows cols);
    Runtime.charge ctx ((n / 16) + 1);
    (match Runtime.copy ctx a.(0) with
     | Array y -> Array { rows; cols; store = y.store; a_owned = true }
     | v -> v)
  | v -> Runtime.fail ctx Type (Messages.index_value (Value.describe v))

let is_ name test = name, nat name 1 1 (fun _ a -> Value.of_bool (test a.(0)))

let rec abs_value ctx v =
  match v with
  | Int i when i = min_int -> Runtime.fail ctx Overflow (Messages.overflow_neg (string_of_int i))
  | Int i -> Int (abs i)
  | Float x -> Float (Float.abs x)
  | True -> Int 1
  | False -> Int 0
  | Missing -> Missing
  | Array _ -> elementwise ctx "abs" abs_value v
  | _ -> Runtime.fail ctx Type (Messages.need_number "abs" (Value.describe v))

and elementwise ctx _name scalar v =
  match v with
  | Array x ->
    Runtime.build ctx (x.rows * x.cols);
    Arrays.of_vals x.rows x.cols (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k)))
  | _ -> scalar ctx v

(* A math function: float to float, element by element. *)
let math1 name f =
  let rec go ctx v =
    match v with
    | Float x -> Float (f x)
    | Int i -> Float (f (float_of_int i))
    | True -> Float (f 1.)
    | False -> Float (f 0.)
    | Missing -> Missing
    | Array { rows; cols; store = F d; _ } ->
      Runtime.build ctx (rows * cols);
      Arrays.of_float rows cols (Kernels.map1 f d)
    | Array _ -> elementwise ctx name go v
    | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))
  in
  name,
  Native { nname = name; perm = None; params = [||]; min_args = 1; max_args = 1; ret_ty = float_of_number;
           run = (fun ctx a -> go ctx a.(0)); f1 = Some f; i2 = None }

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
  | Array _ -> elementwise ctx "sign" sign v
  | _ -> Runtime.fail ctx Type (Messages.need_number "sign" (Value.describe v))

let floats ctx name v =
  match v with
  | Array { store = F d; _ } -> d
  | Array a ->
    Runtime.reserve ctx (a.rows * a.cols);
    Float.Array.init (a.rows * a.cols) (fun k ->
        match Value.elt a k with
        | Int i -> float_of_int i
        | Float x -> x
        | x -> Runtime.fail ctx Type (Messages.need_number name (Value.describe x)))
  | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))

let shape_of ctx name v =
  match v with
  | Array a -> a.rows, a.cols
  | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))

let matmul ctx (a : t array) =
  let r1, c1 = shape_of ctx "matmul" a.(0) and r2, c2 = shape_of ctx "matmul" a.(1) in
  if c1 <> r2 then Runtime.fail ctx Type (Messages.matmul_shape r1 c1 r2 c2);
  let out = Runtime.alloc_float ctx (Runtime.cells ctx r1 c2) 0. in
  Runtime.charge ctx (((r1 * c1 * c2) / 16) + 1);
  let x = floats ctx "matmul" a.(0) and y = floats ctx "matmul" a.(1) in
  Arrays.of_float r1 c2 (Kernels.matmul ~rows:r1 ~cols:c2 ~inner:c1 ~out x y)

let transpose ctx (a : t array) =
  match a.(0) with
  | Array x ->
    let n = x.rows * x.cols in
    Runtime.build ctx n;
    let at k = let j = k / x.rows and i = k mod x.rows in (i * x.cols) + j in
    (match x.store with
     | F d -> Arrays.of_float x.cols x.rows (Kernels.transpose ~rows:x.rows ~cols:x.cols d)
     | V d ->
       let out = Array.make n Missing in
       if n > 0 then Array.iteri (fun k v -> out.(at k) <- Value.share v) d;
       Array { rows = x.cols; cols = x.rows; store = V out; a_owned = true })
  | v -> v

let sum ctx v =
  match v with
  | Array { rows; cols; store = F d; _ } ->
    Runtime.charge ctx (((rows * cols) / 16) + 1);
    Float (Kernels.sum d)
  | Array x ->
    let n = x.rows * x.cols in
    Runtime.charge ctx ((n / 16) + 1);
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

(* min and max: the whole array with one argument, element by element with two. *)
let best name better ctx (a : t array) =
  let pick ctx x y =
    match x, y with
    | Missing, _ | _, Missing -> Missing
    | _ -> if better ctx y x = True then y else x
  in
  if Array.length a = 2 then Arith.broadcast ctx pick a.(0) a.(1)
  else
    match a.(0) with
    | Array x ->
      let n = x.rows * x.cols in
      if n = 0 then Runtime.fail ctx Type (Messages.empty_array name);
      Runtime.charge ctx ((n / 16) + 1);
      let acc = ref (Value.elt x 0) in
      for k = 1 to n - 1 do acc := pick ctx !acc (Value.elt x k) done;
      Value.share !acc
    | v -> v

let mask_all name stop ctx (a : t array) =
  match a.(0) with
  | Array x ->
    let n = x.rows * x.cols in
    Runtime.charge ctx ((n / 16) + 1);
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

let prelude =
  [ "print", nat "print" 0 max_int print;
    "error", nat "error" 1 1 (fun ctx a -> Runtime.fail ctx User (Messages.plain (Value.text_of ctx a.(0))));
    "assert", nat "assert" 1 2 (fun ctx a ->
        match a.(0) with
        | True -> Missing
        | False ->
          let m =
            if Array.length a > 1 then Messages.plain (Value.text_of ctx a.(1)) else Messages.assertion
          in
          Runtime.fail ctx User m
        | v -> Runtime.fail ctx Type (Messages.condition (Value.describe v)));
    "_merge", nat "_merge" 2 2 (fun ctx a ->
        match a.(1) with
        | Struct r ->
          let acc = ref a.(0) in
          Array.iteri
            (fun i name ->
               match !acc with
               | Struct x -> acc := Value.add_field ctx.w x.shape x.fields name (Value.share r.fields.(i))
               | _ -> ())
            r.shape.names;
          !acc
        | v -> v);
    "args", Array { rows = 1; cols = 0; store = V [||]; a_owned = false };
    "text", nat "text" 1 1 (fun ctx a -> Text (Value.text_of ctx a.(0)));
    "length", nat ~ret:(fun _ -> TI) "length" 1 1 (fun _ a -> Int (length a.(0)));
    "div", int_native "div" Arith.int_div;
    "mod", int_native "mod" Arith.int_mod;
    "equal", nat "equal" 2 2 (fun ctx a -> Value.of_bool (Value.equal ctx a.(0) a.(1)));
    "zeros", nat ~ret:fa_size "zeros" 1 2 (fun ctx a -> let r, c = dims ctx "zeros" a 0 in filled ctx (Float 0.) r c);
    "ones", nat ~ret:fa_size "ones" 1 2 (fun ctx a -> let r, c = dims ctx "ones" a 0 in filled ctx (Float 1.) r c);
    "fill", nat "fill" 2 3 (fun ctx a -> let r, c = dims ctx "fill" a 1 in filled ctx a.(0) r c);
    "size", nat "size" 1 2 size;
    "reshape", nat "reshape" 3 3 reshape;
    "abs", nat ~ret:same_number "abs" 1 1 (fun ctx a -> abs_value ctx a.(0));
    math1 "sqrt" sqrt; math1 "exp" exp; math1 "log" log; math1 "sin" sin; math1 "cos" cos; math1 "tan" tan;
    math1 "asin" asin; math1 "acos" acos; math1 "atan" atan;
    rounding "floor" floor; rounding "ceil" ceil; rounding "round" Float.round;
    "sign", nat ~ret:same_number "sign" 1 1 (fun ctx a -> sign ctx a.(0));
    "atan2", nat "atan2" 2 2 (fun ctx a ->
        Arith.broadcast ctx (fun ctx y x ->
            match y, x with
            | Missing, _ | _, Missing -> Missing
            | _ ->
              let num v = match v with
                | Int i -> float_of_int i
                | Float f -> f
                | _ -> Runtime.fail ctx Type (Messages.need_number "atan2" (Value.describe v))
              in
              Float (Float.atan2 (num y) (num x))) a.(0) a.(1));
    "matmul", nat ~ret:fa_size "matmul" 2 2 matmul;
    "transpose", nat ~ret:same_fa "transpose" 1 1 transpose;
    "sum", nat ~ret:scalar_of_fa "sum" 1 1 (fun ctx a -> sum ctx a.(0));
    "mean", nat ~ret:scalar_of_fa "mean" 1 1 (fun ctx a -> mean ctx a.(0));
    "min", nat ~ret:scalar_of_fa "min" 1 2 (best "min" Arith.lt);
    "max", nat ~ret:scalar_of_fa "max" 1 2 (best "max" Arith.gt);
    "any", nat "any" 1 1 (mask_all "any" true);
    "all", nat "all" 1 1 (mask_all "all" false);
    is_ "is_int" (function Int _ -> true | _ -> false);
    is_ "is_float" (function Float _ -> true | _ -> false);
    is_ "is_number" (function Int _ | Float _ -> true | _ -> false);
    is_ "is_bool" (function True | False -> true | _ -> false);
    is_ "is_text" (function Text _ -> true | _ -> false);
    is_ "is_array" (function Array _ -> true | _ -> false);
    is_ "is_struct" (function Struct _ -> true | _ -> false);
    is_ "is_function" (function Fun _ | Native _ -> true | _ -> false);
    is_ "is_missing" (function Missing -> true | _ -> false);
    "pi", Float (4. *. atan 1.);
    "nan", Float nan ]

let register w name value =
  let md = w.modules.(0) in
  let k = Array.length md.cells in
  md.cells <- Array.append md.cells [| value |];
  md.stable <- Array.append md.stable [| true |];
  md.mnames <- (name, k) :: md.mnames
