open Types

type ix = At of int | Slice of int * int | Every | Mask of arr | Key of t

let of_float rows cols d = Array { rows; cols; store = F d; a_owned = true; a_tip = true }

let of_ints rows cols d = Array { rows; cols; store = I d; a_owned = true; a_tip = true }

(* All floats or all integers take the typed storage. *)
let of_vals rows cols (d : t array) =
  if Array.length d > 0 && Array.for_all (function Float _ -> true | _ -> false) d then begin
    let n = Array.length d in
    let f = Float.Array.create n in
    Array.iteri (fun i v -> match v with Float x -> Float.Array.set f i x | _ -> ()) d;
    of_float rows cols f
  end
  else if Array.length d > 0 && Array.for_all (function Int _ -> true | _ -> false) d then
    of_ints rows cols (Array.map (function Int i -> i | _ -> 0) d)
  else Array { rows; cols; store = V d; a_owned = true; a_tip = true }

let list values = if Array.length values = 0 then of_vals 0 0 values else of_vals 1 (Array.length values) values

let int_range ctx lo hi =
  let span = hi - lo in
  if hi >= lo && (span < 0 || span = max_int) then Runtime.fail ctx Overflow Messages.range_too_long;
  let n = if hi < lo then 0 else span + 1 in
  Runtime.pay ctx n;
  let d = Runtime.alloc_ints ctx n 0 in
  for i = 0 to n - 1 do
    d.(i) <- lo + i
  done;
  of_ints 1 n d

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
  | Text _ -> Key v
  | Float x when not (Float.is_integer x) -> Key v
  | _ -> At (whole_index ctx v)

let mem ctx v xs =
  match xs with
  | Array a ->
    let n = a.rows * a.cols in
    Runtime.pay ctx n;
    let rec go k = k < n && (Value.equal ctx v (Value.elt a k) || go (k + 1)) in
    Value.of_bool (go 0)
  | Dict _ | Struct { shape = { sname = None; _ }; _ } -> Value.of_bool (Option.is_some (Dict.get ctx "in" v xs))
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
  | Key k -> Runtime.fail ctx Type (Messages.index_type (Value.describe k))
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
    Runtime.pay ctx n;
    let out = Array.make n 0 and used = ref 0 in
    for k = 0 to n - 1 do
      match Value.elt m k with
      | True ->
        out.(!used) <- k;
        incr used
      | False | Missing -> ()
      | v -> Runtime.fail ctx Type (Messages.index_type (Value.describe v))
    done;
    Array.sub out 0 !used

let pick ctx a (ks : int array) rows cols =
  Runtime.reserve ctx (Array.length ks);
  match a.store with
  | F d ->
    let out = Float.Array.create (Array.length ks) in
    Par.ranges (Array.length ks) (fun lo hi ->
        for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get d ks.(i)) done);
    of_float rows cols out
  | I d ->
    let out = Array.make (Array.length ks) 0 in
    Par.ranges (Array.length ks) (fun lo hi -> for i = lo to hi - 1 do out.(i) <- d.(ks.(i)) done);
    of_ints rows cols out
  | V d -> Array { rows; cols; store = V (Array.map (fun k -> Value.share d.(k)) ks); a_owned = true; a_tip = true }

let not_array ctx v = Runtime.fail ctx Type (Messages.index_value (Value.describe v))

(* The key of an index on a dictionary. *)
let key_of ctx ixs =
  match ixs with
  | [| At i |] -> Int i
  | [| Key k |] -> k
  | _ -> Runtime.fail ctx Index Messages.dict_index

let read1 ctx v ix =
  match v with
  | Dict _ | Struct { shape = { sname = None; _ }; _ } ->
    let k = key_of ctx [| ix |] in
    (match Dict.get ctx "" k v with
     | Some x -> Value.share x
     | None -> Runtime.fail ctx Index (Messages.dict_absent (Value.describe k)))
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

(* A value of another kind converts typed storage to V. In F storage, an integer becomes a float. *)
let store_elt ctx s a k x =
  match a.store, x with
  | F d, Float f -> Float.Array.set d k f
  | F d, Int i -> Float.Array.set d k (float_of_int i)
  | I d, Int i -> d.(k) <- i
  | V d, _ -> d.(k) <- x
  | (F _ | I _), _ ->
    ctx.site <- s;
    let n = a.rows * a.cols in
    Runtime.pay ctx n;
    Runtime.reserve ctx (5 * n);
    let vals = Array.init n (Value.elt a) in
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
  | Array _, [| Key k |] -> Runtime.fail ctx Type (Messages.index_type (Value.describe k))
  | Array _, _ -> Runtime.fail ctx Index Messages.index_write
  | _ -> not_array ctx v

let read ctx v (ixs : ix array) =
  match ixs with
  | [| i |] -> read1 ctx v i
  | [| i; j |] -> read2 ctx v i j
  | _ -> Runtime.fail ctx Index Messages.index_count
