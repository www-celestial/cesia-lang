open Types

(* A direct call doesn't share its arguments, so that measuring a variable leaves it owned. A native returning one of
   its inputs therefore creates the second reference here. *)
let nat ?perm ?(params = [||]) ?(ret = fun _ -> TA) ?(result = false) nname min_args max_args run =
  let run ctx (a : t array) =
    let r = run ctx a in
    if Array.memq r a then Value.share r else r
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

(* Eight bytes at a time (SWAR): a byte that continues a code point is 10xxxxxx, its high bit set and the next one clear,
   which [w land lnot (w lsl 1)] leaves at the high bit; a multiplication adds up those bits. *)
let points_between s a b =
  let n = ref 0 and k = ref a in
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
  | Array _ -> elementwise ctx "Abs" abs_value v
  | _ -> Runtime.fail ctx Type (Messages.need_number "Abs" (Value.describe v))

and elementwise ctx _name scalar v =
  match v with
  | Array x ->
    Runtime.build ctx (x.rows * x.cols);
    Arrays.vals_like x (Array.init (x.rows * x.cols) (fun k -> scalar ctx (Value.elt x k)))
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
    | Array ({ rows; cols; store = F _; _ } as x) ->
      Runtime.build ctx (rows * cols);
      (match (Value.trim x).store with F d -> Arrays.like x (F (Kernels.map1 f d)) | _ -> v)
    | Array _ -> elementwise ctx name go v
    | _ -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))
  in
  name,
  Native { nname = name; perm = None; params = [||]; min_args = 1; max_args = 1; ret_ty = float_of_number;
           run = (fun ctx a -> go ctx a.(0)); f1 = Some f; i2 = None; gives_result = false }

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

(* Knuth, Morris and Pratt: linear, for the long patterns where the plain search could be quadratic. [at i] is the byte i
   of the text, folded or not, of [n] bytes. *)
let find_long at n part from =
  let m = String.length part in
  let fail = Array.make (m + 1) 0 in
  let k = ref 0 in
  for i = 1 to m - 1 do
    while !k > 0 && part.[i] <> part.[!k] do k := fail.(!k) done;
    if part.[i] = part.[!k] then incr k;
    fail.(i + 1) <- !k
  done;
  let rec go i k =
    if k = m then i - m
    else if i >= n then -1
    else if at i = part.[k] then go (i + 1) (k + 1)
    else if k > 0 then go i fail.(k)
    else go (i + 1) 0
  in
  go from 0

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

(* The first position of [part] in [s] from byte [from], or -1. [part] isn't empty. With [fold], the ASCII letters match
   in either case, in both. The rarest byte of [part], by [ranks], is looked for eight bytes at a time (SWAR): the word
   xor that byte repeated has a zero byte where it is; a letter is or'ed with 0x20 in each byte first, which turns its
   capital into it and no other byte. Each place found is then compared whole. *)
let find_from ?(fold = false) s part from =
  let part = if fold then String.lowercase_ascii part else part in
  let n = String.length s and m = String.length part in
  let at i = if fold then Char.lowercase_ascii s.[i] else s.[i] in
  if m >= 32 then find_long at n part from
  else begin
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

(* The pieces of [s] between the occurrences of [sep]. *)
let pieces s sep =
  let rec go from acc =
    match find_from s sep from with
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

(* The byte where code point [k] starts, counting from 0, or the length of [s] past the end. *)
let byte_of_point s k =
  let n = String.length s in
  let rec go i left =
    if i >= n then i
    else if Char.code s.[i] land 0xC0 = 0x80 then go (i + 1) left
    else if left = 0 then i
    else go (i + 1) (left - 1)
  in
  go 0 k

let slice ctx (a : t array) =
  let first = Arrays.whole_index ctx a.(0) and last = Arrays.whole_index ctx a.(1) in
  let s = text_arg ctx "Slice" a.(2) in
  let n = code_points s in
  if first < 1 then Runtime.fail ctx Index (Messages.index_outside first n);
  if last > n then Runtime.fail ctx Index (Messages.index_outside last n);
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
    let rec go from k = match find_from s part from with -1 -> k | p -> go (p + String.length part) (k + 1) in
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
    (* The current folder, for path.Abs, which tells where a path is: as Exists, the read permission on it. *)
    "path", [ "windows", Value.of_bool Sys.win32;
              "here", nat "here" 1 1 (fun ctx a -> Runtime.check_perm ctx Read (Some (text_arg ctx "Abs" a.(0))); Text (Sys.getcwd ())) ];
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
    [ "Text", nat "Text" 1 1 (fun ctx a -> Text (Value.text_of ctx a.(0)));
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
      math1 "Sqrt" sqrt; math1 "Exp" exp; math1 "Log" log; math1 "Sin" sin; math1 "Cos" cos; math1 "Tan" tan;
      math1 "Asin" asin; math1 "Acos" acos; math1 "Atan" atan;
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
      "Pi", Float (4. *. atan 1.);
      "Nan", Float nan ];
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
      "Min", nat ~ret:scalar_of_fa "Min" 1 2 (best "Min" Arith.lt);
      "Max", nat ~ret:scalar_of_fa "Max" 1 2 (best "Max" Arith.gt);
      "Any", nat "Any" 1 1 (mask_all "Any" true);
      "All", nat "All" 1 1 (mask_all "All" false) ] ]
