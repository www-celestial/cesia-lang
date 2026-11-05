open Types

let no_order = [| Undef |]

(* A block holds at most [width] keys; 5 bits of hash a level, 30 bits, so [levels] branches at most above a block. *)
let width = 32

(* Inside a deep map a block holds fewer keys: a write copies one block, and smaller ones copy less. *)
let deep_width = 8
let levels = 6

(* Drawn once per run, so that nobody outside can choose keys that fall together. *)
let seed = Random.State.bits (Random.State.make_self_init ())
let mask = ref 0x3FFF_FFFF

let compare_keys a b =
  match a, b with
  | Int x, Int y -> Int.compare x y
  | Text x, Text y -> String.compare x y
  | Float x, Float y -> Float.compare x y
  | Int x, Float y -> Float.compare (float_of_int x) y
  | Float x, Int y -> Float.compare x (float_of_int y)
  | (Int _ | Float _), _ -> -1
  | _ -> 1

(* 1 and 1.0 are one key, so a number hashes by its value as a float, which an integer below 2^53 is exactly. *)
let exact = 1 lsl 53

let number_hash f =
  if Float.is_integer f && Float.abs f <= 4.611686018427387904e18 then Hashtbl.seeded_hash seed (int_of_float f)
  else Hashtbl.seeded_hash seed f

(* A text 8 bytes at a time, then its last bytes one by one, a multiply each, then mixed: about 4 ns for a name, and no
   allocation. Its quality only spreads the keys; keys that collide on all 30 bits still go to the tree. *)
let text_hash s =
  let n = String.length s in
  let h = ref (seed lxor n) and i = ref 0 in
  while !i + 8 <= n do
    h := (!h lxor Int64.to_int (String.get_int64_le s !i)) * 0x100000001b3;
    h := !h lxor (!h lsr 31);
    i := !i + 8
  done;
  for j = !i to n - 1 do
    h := (!h lxor Char.code s.[j]) * 0x100000001b3
  done;
  let h = (!h lxor (!h lsr 32)) * 0x2545F4914F6CDD1D in
  h lxor (h lsr 29)

let hash k =
  (match k with
   | Text s -> text_hash s
   | Int i when i < exact && i > -exact -> Hashtbl.seeded_hash seed i
   | Int i -> number_hash (float_of_int i)
   | Float f -> number_hash f
   | _ -> 0)
  land !mask

let same a b =
  match a, b with
  | Text x, Text y -> String.equal x y
  | Int x, Int y -> x = y
  | _ -> compare_keys a b = 0

let share v =
  (match v with
   | Array a -> a.a_owned <- false
   | Struct r -> r.r_owned <- false
   | Dict d -> d.d_owned <- false
   | _ -> ());
  v

let whole = max_int
let no_keys = { ks = [||]; hs = [||]; used = whole; deep = Flat }
let keys_of ks = { ks; hs = Array.map hash ks; used = whole; deep = Flat }
let is_whole (k : keys) = k.used = whole
let names names = keys_of (Array.map (fun n -> Text n) names)
let empty () = Dict { keys = no_keys; vals = [||]; d_owned = true }
let record keys vals = Dict { keys; vals; d_owned = true }

(* The place of a key among the first [n], or -1. *)
let index (k : keys) n h key =
  let hs = k.hs in
  let rec go i = if i = n then -1 else if hs.(i) = h && same k.ks.(i) key then i else go (i + 1) in
  go 0

(* The keys of a block of [n] and one more: in place when this map is the one that wrote the most, with room left; else new
   arrays with room for more. *)
let grow keys n key h =
  if n = 0 then { ks = [| key; Undef; Undef; Undef |]; hs = [| h; 0; 0; 0 |]; used = 1; deep = Flat }
  else if keys.used = n && n < Array.length keys.ks then begin
    keys.ks.(n) <- key;
    keys.hs.(n) <- h;
    keys.used <- n + 1;
    keys
  end else begin
    let room = if n < 4 then 4 else if 2 * n < 32 then 2 * n else 32 in
    let ks = Array.make room Undef and hs = Array.make room 0 in
    Array.blit keys.ks 0 ks 0 n;
    Array.blit keys.hs 0 hs 0 n;
    ks.(n) <- key;
    hs.(n) <- h;
    { ks; hs; used = n + 1; deep = Flat }
  end

(* The first [n] of an array and [x] after them. *)
let with_last a n x =
  let b = Array.make (n + 1) x in
  Array.blit a 0 b 0 n;
  b

(* The balanced tree, sorted by key, for keys of equal hashes, and for sets. *)

let tree_length = function Leaf -> 0 | Node n -> n.n
let height = function Leaf -> 0 | Node n -> n.hr land 63
let node l k v rk r hl hr = Node { l; k; v; r; hr = (rk lsl 6) lor (if hl > hr then hl + 1 else hr + 1); n = 1 + tree_length l + tree_length r }
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
let rec tree_insert k v rk = function
  | Leaf -> make Leaf k v rk Leaf
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then Node { n with v }
    else if c < 0 then balance (tree_insert k v rk n.l) n.k n.v (n.hr lsr 6) n.r
    else balance n.l n.k n.v (n.hr lsr 6) (tree_insert k v rk n.r)

let rec tree_find k = function
  | Leaf -> Undef
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then n.v else tree_find k (if c < 0 then n.l else n.r)

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

let rec tree_delete k = function
  | Leaf -> Leaf
  | Node n ->
    let c = compare_keys k n.k in
    if c = 0 then join n.l n.r
    else if c < 0 then balance (tree_delete k n.l) n.k n.v (n.hr lsr 6) n.r
    else balance n.l n.k n.v (n.hr lsr 6) (tree_delete k n.r)

let rec tree_iter f = function
  | Leaf -> ()
  | Node n ->
    tree_iter f n.l;
    f (n.hr lsr 6) n.k n.v;
    tree_iter f n.r

(* The trie. *)

let popcount x =
  let x = x - ((x lsr 1) land 0x5555_5555) in
  let x = (x land 0x3333_3333) + ((x lsr 2) land 0x3333_3333) in
  let x = (x + (x lsr 4)) land 0x0F0F_0F0F in
  ((x * 0x0101_0101) lsr 24) land 0xFF

let frag h level = (h lsr (5 * level)) land 31
let below bits f = popcount (bits land ((1 lsl f) - 1))

(* In a block of the trie: a hash and its rank in one integer, a key and its value side by side. *)
let hash_bits = 0x3FFF_FFFF
let pack h rk = (rk lsl 30) lor h

let block_index (kv : t array) (hr : int array) n h key =
  let rec go i = if i = n then -1 else if hr.(i) land hash_bits = h && same kv.(2 * i) key then i else go (i + 1) in
  go 0

let rec find_node node h key level =
  match node with
  | Block b ->
    let i = block_index b.kv b.hr b.bn h key in
    if i < 0 then Undef else b.kv.((2 * i) + 1)
  | Branch b ->
    let f = frag h level in
    if b.bits land (1 lsl f) = 0 then Undef else find_node b.kids.(below b.bits f) h key (level + 1)
  | Same t -> tree_find key t

let find m h key =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let i = index keys (Array.length vals) h key in
    if i < 0 then Undef else vals.(i)
  | Dict { keys = { deep = Deep d; _ }; _ } -> find_node d.root h key 0
  | _ -> Undef

let length = function
  | Dict { keys = { deep = Flat; _ }; vals; _ } -> Array.length vals
  | Dict { keys = { deep = Deep d; _ }; _ } -> d.size
  | _ -> 0

let append a x =
  let n = Array.length a in
  let b = Array.make (n + 1) x in
  Array.blit a 0 b 0 n;
  b

(* The same for small blocks of values and of hashes: a literal array is made inline, without a call to C. *)
let append_v (a : t array) x =
  match a with
  | [||] -> [| x |]
  | [| a0 |] -> [| a0; x |]
  | [| a0; a1 |] -> [| a0; a1; x |]
  | [| a0; a1; a2 |] -> [| a0; a1; a2; x |]
  | [| a0; a1; a2; a3 |] -> [| a0; a1; a2; a3; x |]
  | [| a0; a1; a2; a3; a4 |] -> [| a0; a1; a2; a3; a4; x |]
  | [| a0; a1; a2; a3; a4; a5 |] -> [| a0; a1; a2; a3; a4; a5; x |]
  | [| a0; a1; a2; a3; a4; a5; a6 |] -> [| a0; a1; a2; a3; a4; a5; a6; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; a13 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; a13; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; a13; a14 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; a13; a14; x |]
  | [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; a13; a14; a15 |] -> [| a0; a1; a2; a3; a4; a5; a6; a7; a8; a9; a10; a11; a12; a13; a14; a15; x |]
  | _ -> append a x

let append_h (a : int array) x =
  match a with
  | [||] -> [| x |]
  | [| a0 |] -> [| a0; x |]
  | [| a0; a1 |] -> [| a0; a1; x |]
  | [| a0; a1; a2 |] -> [| a0; a1; a2; x |]
  | [| a0; a1; a2; a3 |] -> [| a0; a1; a2; a3; x |]
  | [| a0; a1; a2; a3; a4 |] -> [| a0; a1; a2; a3; a4; x |]
  | [| a0; a1; a2; a3; a4; a5 |] -> [| a0; a1; a2; a3; a4; a5; x |]
  | [| a0; a1; a2; a3; a4; a5; a6 |] -> [| a0; a1; a2; a3; a4; a5; a6; x |]
  | _ -> append a x

let remove a i =
  let n = Array.length a in
  Array.init (n - 1) (fun j -> if j < i then a.(j) else a.(j + 1))

let insert_at a s x =
  Array.init (Array.length a + 1) (fun j -> if j < s then a.(j) else if j = s then x else a.(j - 1))

(* The marks of maps: a map changes in place only the nodes of its own mark, and a new mark copies a node once. *)
let marks = ref 0

let fresh () =
  incr marks;
  !marks

(* The node of the entries at the positions [ix], in their order, at [level]: their hashes agree on the levels above. A key
   twice keeps its first place and its last value. [count] gets the keys kept; a block holds at most [cap]; [ed] marks the
   nodes. *)
let rec build (hs : int array) ks vs rs (ix : int array) level count cap ed =
  let n = Array.length ix in
  if n <= cap then begin
    let kk = Array.make n Undef and kh = Array.make n 0 and kv = Array.make n Undef and kr = Array.make n 0 and m = ref 0 in
    Array.iter
      (fun i ->
         let rec at j = if j = !m then -1 else if kh.(j) = hs.(i) && same kk.(j) ks.(i) then j else at (j + 1) in
         let j = at 0 in
         if j >= 0 then kv.(j) <- vs.(i)
         else begin
           kk.(!m) <- ks.(i);
           kh.(!m) <- hs.(i);
           kv.(!m) <- vs.(i);
           kr.(!m) <- rs.(i);
           incr m
         end)
      ix;
    let m = !m in
    count := !count + m;
    (* Room for the owner's next keys. *)
    let room = if cap = deep_width then deep_width else m in
    let kv' = Array.make (2 * room) Undef and hr = Array.make room 0 in
    for j = 0 to m - 1 do
      kv'.(2 * j) <- kk.(j);
      kv'.((2 * j) + 1) <- kv.(j);
      hr.(j) <- pack kh.(j) kr.(j)
    done;
    Block { kv = kv'; hr; bed = ed; bn = m }
  end
  else if level >= levels then begin
    let t = Array.fold_left (fun t i -> tree_insert ks.(i) vs.(i) rs.(i) t) Leaf ix in
    count := !count + tree_length t;
    Same t
  end else begin
    let groups = Array.make 32 [] in
    for j = n - 1 downto 0 do
      let f = frag hs.(ix.(j)) level in
      groups.(f) <- ix.(j) :: groups.(f)
    done;
    let bits = ref 0 and kids = ref [] in
    for f = 31 downto 0 do
      match groups.(f) with
      | [] -> ()
      | g ->
        bits := !bits lor (1 lsl f);
        kids := build hs ks vs rs (Array.of_list g) (level + 1) count deep_width ed :: !kids
    done;
    Branch { bits = !bits; kids = Array.of_list !kids; ed }
  end

let deep root size next ded =
  Dict { keys = { ks = [||]; hs = [||]; used = whole; deep = Deep { root; size; next; order = no_order; ded } }; vals = [||]; d_owned = true }

(* A block of [n] keys and a new one: one more key, or past [width] a deep map. *)
let add_new keys vals n h key v =
  if n < width then Dict { keys = grow keys n key h; vals = append_v vals v; d_owned = true }
  else begin
    let all = Array.init (n + 1) Fun.id and ed = fresh () in
    deep (build (with_last keys.hs n h) (with_last keys.ks n key) (append vals v) all all 0 (ref 0) deep_width ed) (n + 1) (n + 1) ed
  end

(* The node with [key] set to [v]: a node of the mark [ed] changes in place and is given back, another is copied with that
   mark. [added]: set when the key is new. *)
let rec put_node node h key v rk level ed added =
  match node with
  | Block b ->
    let n = b.bn in
    let i = block_index b.kv b.hr n h key in
    if i >= 0 then begin
      if b.bed = ed then begin
        b.kv.((2 * i) + 1) <- v;
        node
      end else begin
        let kv = Array.sub b.kv 0 (2 * n) in
        kv.((2 * i) + 1) <- v;
        Block { kv; hr = Array.sub b.hr 0 n; bed = ed; bn = n }
      end
    end else begin
      added := true;
      if n >= deep_width then begin
        let at j = if j < n then j else -1 in
        let hs = Array.init (n + 1) (fun j -> if at j >= 0 then b.hr.(j) land hash_bits else h)
        and ks = Array.init (n + 1) (fun j -> if at j >= 0 then b.kv.(2 * j) else key)
        and vs = Array.init (n + 1) (fun j -> if at j >= 0 then b.kv.((2 * j) + 1) else v)
        and rs = Array.init (n + 1) (fun j -> if at j >= 0 then b.hr.(j) lsr 30 else rk) in
        build hs ks vs rs (Array.init (n + 1) Fun.id) level (ref 0) deep_width ed
      end
      else if b.bed = ed && n < Array.length b.hr then begin
        (* The owner's block, with room: in place. *)
        b.kv.(2 * n) <- key;
        b.kv.((2 * n) + 1) <- v;
        b.hr.(n) <- pack h rk;
        b.bn <- n + 1;
        node
      end else begin
        let room = if n < 2 then 2 else if 2 * n < deep_width then 2 * n else deep_width in
        let kv = Array.make (2 * room) Undef and hr = Array.make room 0 in
        Array.blit b.kv 0 kv 0 (2 * n);
        Array.blit b.hr 0 hr 0 n;
        kv.(2 * n) <- key;
        kv.((2 * n) + 1) <- v;
        hr.(n) <- pack h rk;
        Block { kv; hr; bed = ed; bn = n + 1 }
      end
    end
  | Branch b ->
    let f = frag h level in
    let bit = 1 lsl f and s = below b.bits f in
    if b.bits land bit = 0 then begin
      added := true;
      let one = Block { kv = [| key; v; Undef; Undef |]; hr = [| pack h rk; 0 |]; bed = ed; bn = 1 } in
      Branch { bits = b.bits lor bit; kids = insert_at b.kids s one; ed }
    end else begin
      let kid = b.kids.(s) in
      let kid' = put_node kid h key v rk (level + 1) ed added in
      if b.ed = ed then begin
        if kid' != kid then b.kids.(s) <- kid';
        node
      end else begin
        let kids = Array.copy b.kids in
        kids.(s) <- kid';
        Branch { b with kids; ed }
      end
    end
  | Same t ->
    let u = tree_insert key v rk t in
    if tree_length u > tree_length t then added := true;
    Same u

(* The map with [key] set to [v], a new one: a key that is there keeps its place, and the values of a copied block are in
   both maps. [m] never changes: natives give new values. *)
let put m h key v =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let n = Array.length vals in
    let i = index keys n h key in
    if i >= 0 then begin
      let vals = Array.map share vals in
      vals.(i) <- v;
      Dict { keys; vals; d_owned = true }
    end else begin
      Array.iter (fun x -> ignore (share x)) vals;
      add_new keys vals n h key v
    end
  | Dict { keys = { deep = Deep d; _ }; _ } ->
    (* Both maps hold these nodes now: the old one must copy before it writes. *)
    ignore (share m);
    let added = ref false and ed = fresh () in
    let root = put_node d.root h key v d.next 0 ed added in
    if !added then deep root (d.size + 1) (d.next + 1) ed else deep root d.size d.next ed
  | _ -> m

(* The same for a map that nothing else holds, a write to a variable: it changes in place, or gives the map that takes its
   place, and its values move without being marked as shared. *)
let put_owned m h key v =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let n = Array.length vals in
    let i = index keys n h key in
    if i >= 0 then begin
      vals.(i) <- v;
      m
    end else add_new keys vals n h key v
  | Dict { keys = { deep = Deep d; _ }; _ } ->
    let added = ref false in
    d.root <- put_node d.root h key v d.next 0 d.ded added;
    if !added then begin
      d.size <- d.size + 1;
      d.next <- d.next + 1
    end;
    d.order <- no_order;
    m
  | _ -> m

(* [put_owned] for a key that a map of one block lacks. *)
let add_absent m h key v =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } -> add_new keys vals (Array.length vals) h key v
  | _ -> put_owned m h key v

(* A copy of a map that someone else holds too: a deep map gets a new mark, so that its writes copy the nodes first. *)
let own_copy m =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    Array.iter (fun x -> ignore (share x)) vals;
    Dict { keys; vals = Array.copy vals; d_owned = true }
  | Dict { keys = { deep = Deep d; _ }; _ } ->
    Dict { keys = { ks = [||]; hs = [||]; used = whole; deep = Deep { root = d.root; size = d.size; next = d.next; order = d.order; ded = fresh () } }; vals = [||]; d_owned = true }
  | _ -> m

let empty_block = Block { kv = [||]; hr = [||]; bed = 0; bn = 0 }
let is_empty = function Block { bn = 0; _ } -> true | _ -> false

let rec drop_node node h key level ed =
  match node with
  | Block b ->
    let n = b.bn in
    let i = block_index b.kv b.hr n h key in
    if i < 0 then node
    else
      Block
        { kv = Array.init (2 * (n - 1)) (fun j -> if j < 2 * i then b.kv.(j) else b.kv.(j + 2));
          hr = Array.init (n - 1) (fun j -> if j < i then b.hr.(j) else b.hr.(j + 1)); bed = ed; bn = n - 1 }
  | Branch b ->
    let f = frag h level in
    if b.bits land (1 lsl f) = 0 then node
    else begin
      let s = below b.bits f in
      let kid = drop_node b.kids.(s) h key (level + 1) ed in
      if kid == b.kids.(s) then node
      else if is_empty kid then
        (if b.bits = 1 lsl f then empty_block else Branch { bits = b.bits lxor (1 lsl f); kids = remove b.kids s; ed })
      else if b.ed = ed then begin
        b.kids.(s) <- kid;
        node
      end else begin
        let kids = Array.copy b.kids in
        kids.(s) <- kid;
        Branch { b with kids; ed }
      end
    end
  | Same t ->
    let u = tree_delete key t in
    if tree_length u = tree_length t then node else match u with Leaf -> empty_block | _ -> Same u

let drop m h key =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let n = Array.length vals in
    let i = index keys n h key in
    if i < 0 then m
    else
      Dict
        { keys = { ks = remove (Array.sub keys.ks 0 n) i; hs = remove (Array.sub keys.hs 0 n) i; used = whole; deep = Flat };
          vals = Array.map share (remove vals i); d_owned = true }
  | Dict { keys = { deep = Deep d; _ }; _ } ->
    let ed = fresh () in
    let root = drop_node d.root h key 0 ed in
    if root != d.root then ignore (share m);
    if root == d.root then m else deep root (d.size - 1) d.next ed
  | _ -> m

let rec iter_node f = function
  | Block b ->
    for i = 0 to b.bn - 1 do
      f (b.hr.(i) lsr 30) b.kv.(2 * i) b.kv.((2 * i) + 1)
    done
  | Branch b -> Array.iter (iter_node f) b.kids
  | Same t -> tree_iter f t

(* A deep map sorts its keys by rank once and keeps them with itself: it never changes. Ranks are unique, so when they are few
   each key goes to its rank, and only the gaps left by dropped keys are closed. *)
let deep_items root size next =
  if next <= (2 * size) + 8 then begin
    let at = Array.make (2 * next) Undef in
    iter_node (fun r k v -> at.(2 * r) <- k; at.((2 * r) + 1) <- v) root;
    if next = size then at
    else begin
      let o = Array.make (2 * size) Undef and j = ref 0 in
      for r = 0 to next - 1 do
        if at.(2 * r) != Undef then begin
          o.(!j) <- at.(2 * r);
          o.(!j + 1) <- at.((2 * r) + 1);
          j := !j + 2
        end
      done;
      o
    end
  end else begin
    let all = ref [] in
    iter_node (fun r k v -> all := (r, k, v) :: !all) root;
    let sorted = Array.of_list !all in
    Array.sort (fun (a, _, _) (b, _, _) -> Int.compare a b) sorted;
    Array.init (2 * size) (fun j -> let _, k, x = sorted.(j / 2) in if j land 1 = 0 then k else x)
  end

let items m =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } -> Array.init (2 * Array.length vals) (fun j -> if j land 1 = 0 then keys.ks.(j / 2) else vals.(j / 2))
  | Dict { keys = { deep = Deep d; _ }; _ } when d.order != no_order -> d.order
  | Dict { keys = { deep = Deep d; _ }; _ } ->
    let o = deep_items d.root d.size d.next in
    d.order <- o;
    o
  | _ -> [||]

(* Each key of the map and its value, in no order. *)
let iter f m =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } -> Array.iteri (fun i v -> f keys.ks.(i) v) vals
  | Dict { keys = { deep = Deep d; _ }; _ } -> iter_node (fun _ k v -> f k v) d.root
  | _ -> ()

(* Two keys written the same way: the keys of a map can be shared with another only then, as 1 and 1.0 are one key but don't
   print alike. *)
let alike a b = match a, b with Text x, Text y -> String.equal x y | Int x, Int y -> x = y | _ -> false

(* The keys k1 v1 k2 v2..., already checked: a later key replaces the value and keeps the place. With the same keys in the same
   order as [like], the map shares them. *)
let of_items ?(like = no_keys) (a : t array) =
  let n = Array.length a / 2 in
  let rec fits i = i = n || (alike like.ks.(i) a.(2 * i) && fits (i + 1)) in
  if n > 0 && is_whole like && n = Array.length like.ks && fits 0 then record like (Array.init n (fun i -> a.((2 * i) + 1)))
  else begin
    let hs = Array.init n (fun i -> hash a.(2 * i)) and ks = Array.init n (fun i -> a.(2 * i)) and vs = Array.init n (fun i -> a.((2 * i) + 1)) in
    let all = Array.init n Fun.id and count = ref 0 in
    let ed = fresh () in
    match build hs ks vs all all 0 count width ed with
    | Block b ->
      let n = b.bn in
      record { ks = Array.init n (fun i -> b.kv.(2 * i)); hs = Array.init n (fun i -> b.hr.(i) land hash_bits); used = whole; deep = Flat }
        (Array.init n (fun i -> b.kv.((2 * i) + 1)))
    | root -> deep root !count n ed
  end

let keys_of_map = function Dict { keys = { deep = Flat; _ } as keys; _ } when is_whole keys -> keys | _ -> no_keys

(* Whole keys of [n] and one more, for a name written in the code, which the maps that come through share. *)
let extend keys n key h = { ks = with_last keys.ks n key; hs = with_last keys.hs n h; used = whole; deep = Flat }
