open Types

let compare_keys = Value.compare_keys

let is_key = function
  | Int _ | Text _ -> true
  | Float x -> not (Float.is_nan x)
  | _ -> false

let check ctx k = if not (is_key k) then Runtime.fail ctx Type (Messages.dict_key (Value.describe k))

let height = function Leaf -> 0 | Node n -> n.hr land 63
let length = Value.tree_length
let node l k v rk r hl hr = Node { l; k; v; r; hr = (rk lsl 6) lor (if hl > hr then hl + 1 else hr + 1); n = 1 + length l + length r }
let make l k v rk r = node l k v rk r (height l) (height r)

let balance l k v rk r =
  let hl = height l and hr = height r in
  if hl > hr + 1 then begin
    match l with
    | Node { l = ll; k = lk; v = lv; r = lr; hr = lh; _ } when height ll >= height lr -> make ll lk lv (lh lsr 6) (make lr k v rk r)
    | Node { l = ll; k = lk; v = lv; r = Node m; hr = lh; _ } ->
      make (make ll lk lv (lh lsr 6) m.l) m.k m.v (m.hr lsr 6) (make m.r k v rk r)
    | _ -> assert false
  end else if hr > hl + 1 then begin
    match r with
    | Node { l = rl; k = rk'; v = rv; r = rr; hr = rh; _ } when height rr >= height rl -> make (make l k v rk rl) rk' rv (rh lsr 6) rr
    | Node { l = Node m; k = rk'; v = rv; r = rr; hr = rh; _ } ->
      make (make l k v rk m.l) m.k m.v (m.hr lsr 6) (make m.r rk' rv (rh lsr 6) rr)
    | _ -> assert false
  end else node l k v rk r hl hr

(* A key that is there keeps its rank, so its place in the order. *)
let rec insert k v rk = function
  | Leaf -> make Leaf k v rk Leaf
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then Node { n with k; v }
    else if c < 0 then balance (insert k v rk n.l) n.k n.v (n.hr lsr 6) n.r
    else balance n.l n.k n.v (n.hr lsr 6) (insert k v rk n.r)

let add ctx k v d =
  check ctx k;
  insert k v 0 d

let find ctx k d =
  check ctx k;
  Value.lookup k d

let rec smallest = function
  | Node { l = Leaf; k; v; hr; _ } -> k, v, hr lsr 6
  | Node n -> smallest n.l
  | Leaf -> assert false

let rec without_smallest = function
  | Node { l = Leaf; r; _ } -> r
  | Node n -> balance (without_smallest n.l) n.k n.v (n.hr lsr 6) n.r
  | Leaf -> assert false

let join l r =
  match l, r with
  | Leaf, d | d, Leaf -> d
  | _ ->
    let k, v, rk = smallest r in
    balance l k v rk (without_smallest r)

let rec delete k = function
  | Leaf -> Leaf
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then join n.l n.r
    else if c < 0 then balance (delete k n.l) n.k n.v (n.hr lsr 6) n.r
    else balance n.l n.k n.v (n.hr lsr 6) (delete k n.r)

let tree tree next = Dict { tree; next; order = Value.no_order }
let empty = tree Leaf 0

(* Keys from data, more than [most] keys or past [cap] shapes: a tree, which no choice of keys slows down, and which never
   makes shapes, so data can't make memory grow. *)
let most = 16
let cap = 10_000

let of_items ctx (a : t array) =
  let n = Array.length a / 2 in
  let rec go i d = if i >= n then d else (check ctx a.(2 * i); go (i + 1) (insert a.(2 * i) a.((2 * i) + 1) i d)) in
  let d = go 0 Leaf in
  (* Without a key twice, the order is the one given. *)
  if length d = n && Array.length a = 2 * n then Dict { tree = d; next = n; order = a } else tree d n

let of_struct (r : t array) (shape : shape) =
  let d = ref Leaf in
  (* The values are in both maps now: a write through one must copy them first. *)
  Array.iteri (fun i name -> d := insert (Text name) (Value.share r.(i)) i !d) shape.names;
  tree !d (Array.length r)

let not_map ctx name v =
  match v with
  | Struct { shape = { sname = Some sn; _ }; _ } -> Runtime.fail ctx Type (Messages.map_of_struct name sn)
  | _ -> Runtime.fail ctx Type (Messages.need_dict name (Value.describe v))

let get ctx name k m =
  match m with
  | Dict d -> find ctx k d.tree
  | Struct { shape = { sname = None; _ } as shape; fields; _ } ->
    (match k with
     | Text s ->
       let i = Value.field_index shape s in
       if i >= 0 then Some fields.(i) else None
     | _ ->
       check ctx k;
       None)
  | _ -> not_map ctx name m

let rec put ctx name k v m =
  match m with
  | Dict d ->
    check ctx k;
    let t = insert k v d.next d.tree in
    tree t (if length t > length d.tree then d.next + 1 else d.next)
  | Struct { shape = { sname = None; _ } as shape; fields; _ } ->
    let i = (match k with Text s -> Value.field_index shape s | _ -> -1) in
    if i >= 0 then begin
      let fields = Array.map Value.share fields in
      fields.(i) <- v;
      Struct { shape; fields; r_owned = true }
    end else put ctx name k v (of_struct fields shape)
  | _ -> not_map ctx name m

let drop ctx name k m =
  match m with
  | Dict d ->
    check ctx k;
    let t = delete k d.tree in
    if length t = length d.tree then m else tree t d.next
  | Struct { shape = { sname = None; _ } as shape; fields; _ } ->
    (match k with
     | Text s when Value.field_index shape s >= 0 -> (match of_struct fields shape with Dict d -> tree (delete k d.tree) d.next | x -> x)
     | _ ->
       check ctx k;
       m)
  | _ -> not_map ctx name m

let add_name ctx m name x =
  match m with
  | Struct ({ shape = { sname = None; _ }; _ } as r)
    when Value.field_index r.shape name < 0 && Array.length r.fields < most
         && (Hashtbl.mem r.shape.next name || Hashtbl.length ctx.w.shapes < cap) ->
    Value.add_field ctx.w r.shape r.fields name x
  | _ -> put ctx "" (Text name) x m

let items ctx name m =
  match m with
  | Dict _ | Struct { shape = { sname = None; _ }; _ } -> Value.items m
  | _ -> not_map ctx name m
