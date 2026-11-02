open Types

let compare_keys a b =
  match a, b with
  | Int x, Int y -> Int.compare x y
  | Text x, Text y -> String.compare x y
  | Float x, Float y -> Float.compare x y
  | Int x, Float y -> Float.compare (float_of_int x) y
  | Float x, Int y -> Float.compare x (float_of_int y)
  | (Int _ | Float _), _ -> -1
  | _ -> 1

let is_key = function
  | Int _ | Text _ -> true
  | Float x -> not (Float.is_nan x)
  | _ -> false

let check ctx k = if not (is_key k) then Runtime.fail ctx Type (Messages.dict_key (Value.describe k))

let height = function Leaf -> 0 | Node n -> n.h
let length = function Leaf -> 0 | Node n -> n.n
let make l k v r = Node { l; k; v; r; h = 1 + max (height l) (height r); n = 1 + length l + length r }

let balance l k v r =
  let hl = height l and hr = height r in
  if hl > hr + 1 then begin
    match l with
    | Node { l = ll; k = lk; v = lv; r = lr; _ } when height ll >= height lr -> make ll lk lv (make lr k v r)
    | Node { l = ll; k = lk; v = lv; r = Node m; _ } -> make (make ll lk lv m.l) m.k m.v (make m.r k v r)
    | _ -> assert false
  end else if hr > hl + 1 then begin
    match r with
    | Node { l = rl; k = rk; v = rv; r = rr; _ } when height rr >= height rl -> make (make l k v rl) rk rv rr
    | Node { l = Node m; k = rk; v = rv; r = rr; _ } -> make (make l k v m.l) m.k m.v (make m.r rk rv rr)
    | _ -> assert false
  end else make l k v r

let rec insert k v = function
  | Leaf -> make Leaf k v Leaf
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then Node { n with k; v }
    else if c < 0 then balance (insert k v n.l) n.k n.v n.r
    else balance n.l n.k n.v (insert k v n.r)

let add ctx k v d =
  check ctx k;
  insert k v d

let rec lookup k = function
  | Leaf -> None
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then Some n.v else lookup k (if c < 0 then n.l else n.r)

let find ctx k d =
  check ctx k;
  lookup k d

let rec smallest = function
  | Node { l = Leaf; k; v; _ } -> k, v
  | Node n -> smallest n.l
  | Leaf -> assert false

let rec without_smallest = function
  | Node { l = Leaf; r; _ } -> r
  | Node n -> balance (without_smallest n.l) n.k n.v n.r
  | Leaf -> assert false

let join l r =
  match l, r with
  | Leaf, d | d, Leaf -> d
  | _ ->
    let k, v = smallest r in
    balance l k v (without_smallest r)

let rec delete k = function
  | Leaf -> Leaf
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then join n.l n.r
    else if c < 0 then balance (delete k n.l) n.k n.v n.r
    else balance n.l n.k n.v (delete k n.r)

let remove ctx k d =
  check ctx k;
  delete k d
