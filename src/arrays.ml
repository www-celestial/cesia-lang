open Types

type ix = At of int | Slice of int * int | Every | Mask of arr

let of_float rows cols d = Array { rows; cols; store = F d; a_owned = true }

let of_vals rows cols (d : t array) =
  if Array.length d > 0 && Array.for_all (function Float _ -> true | _ -> false) d then begin
    let n = Array.length d in
    let f = Float.Array.create n in
    Array.iteri (fun i v -> match v with Float x -> Float.Array.set f i x | _ -> ()) d;
    of_float rows cols f
  end
  else Array { rows; cols; store = V d; a_owned = true }

let int_range ctx lo hi =
  let span = hi - lo in
  if hi >= lo && (span < 0 || span = max_int) then Runtime.fail ctx Overflow Messages.range_too_long;
  let n = if hi < lo then 0 else span + 1 in
  Runtime.charge ctx ((n / 16) + 1);
  let d = Runtime.alloc_vals ctx n Missing in
  for i = 0 to n - 1 do
    d.(i) <- Int (lo + i)
  done;
  Array { rows = 1; cols = n; store = V d; a_owned = true }

let range_bound ctx v =
  match v with
  | Int i -> i
  | Float x when Float.is_integer x && Float.abs x < 4e18 -> int_of_float x
  | _ -> Runtime.fail ctx Type (Messages.range_bound (Value.describe v))

let whole_index ctx v =
  match v with
  | Int i -> i
  | Float x when Float.is_integer x && Float.abs x < 4e18 -> int_of_float x
  | _ -> Runtime.fail ctx Type (Messages.index_type (Value.describe v))

let ix_of ctx v =
  match v with
  | Array a -> Mask a
  | _ -> At (whole_index ctx v)

let mem ctx v xs =
  match xs with
  | Array a ->
    let n = a.rows * a.cols in
    Runtime.charge ctx ((n / 16) + 1);
    let rec go k = k < n && (Value.equal ctx v (Value.elt a k) || go (k + 1)) in
    Value.of_bool (go 0)
  | _ -> Runtime.fail ctx Type (Messages.cant_in (Value.describe xs))

let check1 ctx a i =
  let n = a.rows * a.cols in
  if i < 1 || i > n then Runtime.fail ctx Index (Messages.index_outside i n)

let check2 ctx a i j =
  if i < 1 || i > a.rows || j < 1 || j > a.cols then
    Runtime.fail ctx Index (Messages.index_outside2 i j a.rows a.cols)

(* The positions, from 0, that an index selects in a dimension of size n. *)
let positions ctx n ix =
  let outside i = Runtime.fail ctx Index (Messages.index_outside i n) in
  match ix with
  | At i ->
    if i < 1 || i > n then outside i;
    [| i - 1 |]
  | Every ->
    Runtime.build ctx n;
    Array.init n Fun.id
  | Slice (l, h) ->
    if l > h then [||]
    else begin
      if l < 1 then outside l;
      if h > n then outside h;
      Runtime.build ctx (h - l + 1);
      Array.init (h - l + 1) (fun k -> l - 1 + k)
    end
  | Mask m ->
    let got = m.rows * m.cols in
    if got <> n then Runtime.fail ctx Index (Messages.mask_size got n);
    Runtime.charge ctx ((n / 16) + 1);
    let out = ref [] in
    for k = n - 1 downto 0 do
      match Value.elt m k with
      | True -> out := k :: !out
      | False | Missing -> ()
      | v -> Runtime.fail ctx Type (Messages.index_type (Value.describe v))
    done;
    Array.of_list !out

let pick ctx a (ks : int array) rows cols =
  Runtime.reserve ctx (Array.length ks);
  match a.store with
  | F d -> of_float rows cols (Float.Array.init (Array.length ks) (fun i -> Float.Array.get d ks.(i)))
  | V d -> Array { rows; cols; store = V (Array.map (fun k -> Value.share d.(k)) ks); a_owned = true }

let not_array ctx v = Runtime.fail ctx Type (Messages.index_value (Value.describe v))

let read1 ctx v ix =
  match v with
  | Array a ->
    (match ix with
     | At i ->
       check1 ctx a i;
       Value.elt a (i - 1)
     | _ ->
       let ks = positions ctx (a.rows * a.cols) ix in
       let k = Array.length ks in
       if a.cols = 1 && a.rows <> 1 then pick ctx a ks k 1 else pick ctx a ks 1 k)
  | _ -> not_array ctx v

let read2 ctx v ix jx =
  match v with
  | Array a ->
    (match ix, jx with
     | At i, At j ->
       check2 ctx a i j;
       Value.elt a (((j - 1) * a.rows) + i - 1)
     | _ ->
       let rows = positions ctx a.rows ix and cols = positions ctx a.cols jx in
       let r = Array.length rows and c = Array.length cols in
       let ks = Array.make (r * c) 0 in
       Array.iteri
         (fun j cj -> Array.iteri (fun i ri -> ks.((j * r) + i) <- (cj * a.rows) + ri) rows)
         cols;
       pick ctx a ks r c)
  | _ -> not_array ctx v

(* A non-numeric value converts F storage to V; an integer becomes a float. *)
let store_elt ctx s a k x =
  match a.store, x with
  | F d, Float f -> Float.Array.set d k f
  | F d, Int i -> Float.Array.set d k (float_of_int i)
  | V d, _ -> d.(k) <- x
  | F d, _ ->
    ctx.site <- s;
    let n = Float.Array.length d in
    Runtime.charge ctx ((n / 16) + 1);
    Runtime.reserve ctx (5 * n);
    let vals = Array.init n (fun i -> Float (Float.Array.get d i)) in
    vals.(k) <- x;
    a.store <- V vals

let write ctx v (ixs : ix array) x =
  match v, ixs with
  | Array a, [| At i |] ->
    check1 ctx a i;
    store_elt ctx ctx.site a (i - 1) x
  | Array a, [| At i; At j |] ->
    check2 ctx a i j;
    store_elt ctx ctx.site a (((j - 1) * a.rows) + i - 1) x
  | Array _, _ -> Runtime.fail ctx Index Messages.index_write
  | _ -> not_array ctx v

let read ctx v (ixs : ix array) =
  match ixs with
  | [| i |] -> read1 ctx v i
  | [| i; j |] -> read2 ctx v i j
  | _ -> Runtime.fail ctx Index Messages.index_count
