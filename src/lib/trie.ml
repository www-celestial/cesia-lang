open Types

let no_order = [| Undef |]

(* A map of one block holds at most [width] keys; past them, a trie of 5 bits of hash a level, 30 bits, so [levels] levels
   of nodes at most, and the keys of equal hashes in a tree below them. *)
let width = 32
let levels = 6

(* Drawn once per run, 62 bits, so that nobody outside can choose keys that fall together. *)
let seed, seed2 =
  let st = Random.State.make_self_init () in
  let draw () = (Random.State.bits st lsl 32) lxor (Random.State.bits st lsl 2) lxor Random.State.bits st in
  let a = draw () in
  a, draw ()

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

(* An integer, mixed with the seed: two multiplies by odd numbers and shifts, a bijection, so no two integers share their
   63 bits, and the 30 that place a key depend on the seed. *)
let int_hash i =
  let x = (i lxor seed) * 0x2545F4914F6CDD1D in
  let x = (x lxor (x lsr 29)) * 0x3C79AC492BA7B653 in
  x lxor (x lsr 32) lxor seed2

let number_hash f =
  if Float.is_integer f && Float.abs f <= 4.611686018427387904e18 then int_hash (int_of_float f)
  else Hashtbl.seeded_hash seed f

(* A text 8 bytes at a time, then its last bytes one by one, a multiply each, then mixed with the seed again: about 4 ns for
   a name, and no allocation. Every bit counts: the 64th of each word, which an OCaml integer can't hold, goes in by
   itself, so no two texts fall together whatever the seed. Keys that collide on all 30 bits still go to the tree. *)
let text_hash s =
  let n = String.length s in
  let h = ref (seed lxor n) and i = ref 0 in
  while !i + 8 <= n do
    let w = String.get_int64_le s !i in
    h := ((!h lxor Int64.to_int w) * 0x100000001b3) lxor Int64.to_int (Int64.shift_right_logical w 63);
    h := !h lxor (!h lsr 31);
    i := !i + 8
  done;
  for j = !i to n - 1 do
    h := (!h lxor Char.code s.[j]) * 0x100000001b3
  done;
  let h = (!h lxor (!h lsr 32) lxor seed2) * 0x2545F4914F6CDD1D in
  h lxor (h lsr 29)

let hash k =
  (match k with
   | Text s -> text_hash s
   | Int i when i < exact && i > -exact -> int_hash i
   | Int i -> number_hash (float_of_int i)
   | Float f -> number_hash f
   | _ -> 0)
  land !mask

let[@inline] hash_int i = (if i < exact && i > -exact then int_hash i else number_hash (float_of_int i)) land !mask
let hash_float f = number_hash f land !mask
let hash_text s = text_hash s land !mask

let same a b =
  match a, b with
  | Text x, Text y -> String.equal x y
  | Int x, Int y -> x = y
  | _ -> compare_keys a b = 0

let[@inline] share v =
  (match v with
   | Array a -> a.a_owned <- false
   | Struct r -> r.r_owned <- false
   | Dict d -> d.d_owned <- false
   | _ -> ());
  v

(* The values of a map of one block, in their store: F while every one is a float, V otherwise. *)
let no_vals = V [||]
let nvals = function F d -> Float.Array.length d | V d -> Array.length d | I d -> Array.length d
let[@inline] vget s i = match s with V d -> d.(i) | F d -> Float (Float.Array.get d i) | I d -> Int d.(i)
let rec all_floats (vs : t array) i n = i = n || (match vs.(i) with Float _ -> all_floats vs (i + 1) n | _ -> false)

let vals_of (vs : t array) =
  let n = Array.length vs in
  if n = 0 || not (all_floats vs 0 n) then V vs
  else begin
    let d = Float.Array.create n in
    for i = 0 to n - 1 do match vs.(i) with Float f -> Float.Array.set d i f | _ -> () done;
    F d
  end

(* The store of two, three or four values, made without an array between: the literals of the interpreter. *)
let vals2 x y = match x, y with Float p, Float q -> let d = Float.Array.create 2 in Float.Array.set d 0 p; Float.Array.set d 1 q; F d | _ -> V [| x; y |]

let vals3 x y z =
  match x, y, z with
  | Float p, Float q, Float r -> let d = Float.Array.create 3 in Float.Array.set d 0 p; Float.Array.set d 1 q; Float.Array.set d 2 r; F d
  | _ -> V [| x; y; z |]

let vals4 x y z w =
  match x, y, z, w with
  | Float p, Float q, Float r, Float u ->
    let d = Float.Array.create 4 in
    Float.Array.set d 0 p;
    Float.Array.set d 1 q;
    Float.Array.set d 2 r;
    Float.Array.set d 3 u;
    F d
  | _ -> V [| x; y; z; w |]

(* The values as an array of their own, or the V store's array itself. *)
let vals_array = function V d -> d | s -> Array.init (nvals s) (vget s)

(* Value [i] of an owned map of one block or struct, in place: another value than a float turns its F store into V,
   once. *)
let vset m i x =
  match m, x with
  | (Dict { vals = V d; _ } | Struct { fields = V d; _ }), _ -> d.(i) <- x
  | (Dict { vals = F d; _ } | Struct { fields = F d; _ }), Float f -> Float.Array.set d i f
  | Dict r, _ ->
    let d = vals_array r.vals in
    d.(i) <- x;
    r.vals <- V d
  | Struct r, _ ->
    let d = vals_array r.fields in
    d.(i) <- x;
    r.fields <- V d
  | _ -> ()

let whole = max_int
let no_keys = { ks = [||]; hs = [||]; used = whole; deep = Flat }
let keys_of ks = { ks; hs = Array.map hash ks; used = whole; deep = Flat }
let is_whole (k : keys) = k.used = whole
let names names = keys_of (Array.map (fun n -> Text n) names)
let empty () = Dict { keys = no_keys; vals = no_vals; d_owned = true }
let record keys vals = Dict { keys; vals = vals_of vals; d_owned = true }

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

(* The trie: the nodes of CHAMP, Steindorfer and Vinju's compressed hash-array mapped prefix tree (OOPSLA 2015). A node
   holds inline each key whose 5 bits of hash at its level no other key under it shares, and a node of the next level for
   the bits that several share: no node holds a lone key below it, so a map is as deep as its hashes make it and no deeper,
   and its arrays hold no room but the owner's. *)

let popcount x =
  let x = x - ((x lsr 1) land 0x5555_5555) in
  let x = (x land 0x3333_3333) + ((x lsr 2) land 0x3333_3333) in
  let x = (x + (x lsr 4)) land 0x0F0F_0F0F in
  ((x * 0x0101_0101) lsr 24) land 0xFF

let[@inline] frag h level = (h lsr (5 * level)) land 31

(* The place of [bit] among the bits set in [map]. *)
let[@inline] place map bit = popcount (map land (bit - 1))

(* A hash and its rank in one integer. *)
let hash_bits = 0x3FFF_FFFF
let pack h rk = (rk lsl 30) lor h

let empty_node = Champ { dmap = 0; nmap = 0; kv = [||]; hr = [||]; kids = [||]; ed = 0 }

(* Set by a write when its key is new. *)
let added = ref false

(* The table of a deep map that nothing else ever held (Python 3.6's compact dict, after Raymond Hettinger): at most half
   of [tslots] used, a key there is found in 1.5 probes on average and one that isn't in 2.5 (Knuth, vol. 3, 6.4), against
   the four or five nodes of the trie; the entries in the order of insertion, which is the map's order. *)
let low32 = 0xFFFF_FFFF

(* Random keys don't run this far from the home slot of a new key: at this load, a simulation found 45 slots at most in ten
   runs of a million keys, and 51 in two of four million. Such a probe means keys that fall together, and the map becomes
   the trie, whose depth no choice of keys changes. *)
let probe_limit = 128

let[@inline] tget tv e = match tv with I d -> Int d.(e) | V d -> d.(e) | F d -> Float (Float.Array.get d e)

(* Entry [e] set to [v]: an integer stays one in an [I] store; another value makes the store [V], once. *)
let tset t e v =
  match t.tvals, v with
  | I d, Int i -> d.(e) <- i
  | V d, _ -> d.(e) <- v
  | tv, _ ->
    let d = Array.make (Array.length t.tkeys) Undef in
    for j = 0 to t.tcount - 1 do d.(j) <- tget tv j done;
    d.(e) <- v;
    t.tvals <- V d

(* The slot of [key] from slot [i] on, or the first empty one: no closure, as a read must allocate nothing. *)
let rec probe (slots : int array) (ks : t array) h key i =
  let s = slots.(i) in
  if s = 0 || (s lsr 32 = h && same ks.((s land low32) - 1) key) then i
  else probe slots ks h key ((i + 1) land (Array.length slots - 1))

let table_find t h key =
  let s = t.tslots.(probe t.tslots t.tkeys h key (h land (Array.length t.tslots - 1))) in
  if s = 0 then Undef else tget t.tvals ((s land low32) - 1)

let rec settle (slots : int array) s i =
  if slots.(i) = 0 then slots.(i) <- s else settle slots s ((i + 1) land (Array.length slots - 1))

(* Twice the entries and twice the slots, the slots placed again from their hashes. *)
let grow_table t =
  let cap = 2 * Array.length t.tkeys in
  let extend a fill = let b = Array.make cap fill in Array.blit a 0 b 0 t.tcount; b in
  t.tkeys <- extend t.tkeys Undef;
  t.tvals <- (match t.tvals with I d -> I (extend d 0) | V d -> V (extend d Undef) | tv -> V (Array.init cap (fun j -> if j < t.tcount then tget tv j else Undef)));
  let slots = Array.make (2 * cap) 0 and mask = (2 * cap) - 1 in
  for i = 0 to Array.length t.tslots - 1 do
    let s = t.tslots.(i) in
    if s <> 0 then settle slots s ((s lsr 32) land mask)
  done;
  t.tslots <- slots

(* [key] set to [v] in place; false, and nothing changed, when the probe of a new key passes [probe_limit]. *)
let table_put t h key v =
  if t.tcount = Array.length t.tkeys then grow_table t;
  let slots = t.tslots in
  let home = h land (Array.length slots - 1) in
  let i = probe slots t.tkeys h key home in
  let s = slots.(i) in
  if s <> 0 then (tset t ((s land low32) - 1) v; true)
  else
    (i - home) land (Array.length slots - 1) <= probe_limit
    && begin
      let e = t.tcount in
      slots.(i) <- (h lsl 32) lor (e + 1);
      t.tkeys.(e) <- key;
      tset t e v;
      t.tcount <- e + 1;
      added := true;
      true
    end

(* A table of the first [n] keys, hashes and values, in this order: a key twice keeps its first place and its last value.
   None when a probe runs too long. *)
let table_of (hs : int array) (ks : t array) (vs : t array) n =
  let cap = ref 64 in
  while !cap < n do cap := 2 * !cap done;
  let rec ints i = i = n || (match vs.(i) with Int _ -> ints (i + 1) | _ -> false) in
  let t = { tslots = Array.make (2 * !cap) 0; tkeys = Array.make !cap Undef; tvals = (if ints 0 then I (Array.make !cap 0) else V (Array.make !cap Undef)); tcount = 0 } in
  let rec go i = i = n || (table_put t hs.(i) ks.(i) vs.(i) && go (i + 1)) in
  if go 0 then Some t else None

(* The six fragments of 5 bits of a hash in the other order, the first level's in the highest bits: sorted by it, the keys
   under each node of the trie are next to each other, and those of each of its bits too. Its own inverse. *)
let reversed h =
  ((h land 31) lsl 25) lor (((h lsr 5) land 31) lsl 20) lor (((h lsr 10) land 31) lsl 15) lor (((h lsr 15) land 31) lsl 10)
  lor (((h lsr 20) land 31) lsl 5) lor ((h lsr 25) land 31)

(* The bits of [level] of a sorted entry, and its number. *)
let[@inline] bits_at (b : int array) j level = (b.(j) lsr (32 + (5 * (levels - 1 - level)))) land 31
let[@inline] entry_at (b : int array) j = b.(j) land low32

(* The trie of a table, each node made once at its size. Each entry as its hash reversed * 2^32 + its number, sorted by a
   radix sort of three passes of 10 bits, so the entries of a node of the trie are a run of the array: a bit of the node
   with one entry holds it inline, a bit of more a node of the next level made from that run, and past the last level the
   tree of equal hashes. The ranks are the entries' numbers. *)
let to_trie t ed =
  let n = t.tcount in
  let a = Array.make n 0 and b = Array.make n 0 and c = Array.make 1024 0 and j = ref 0 in
  Array.iter (fun s -> if s <> 0 then (a.(!j) <- (reversed (s lsr 32) lsl 32) lor ((s land low32) - 1); incr j)) t.tslots;
  let pass shift (src : int array) (dst : int array) =
    Array.fill c 0 1024 0;
    for j = 0 to n - 1 do
      let d = (src.(j) lsr shift) land 1023 in
      c.(d) <- c.(d) + 1
    done;
    let sum = ref 0 in
    for d = 0 to 1023 do
      let x = c.(d) in
      c.(d) <- !sum;
      sum := !sum + x
    done;
    for j = 0 to n - 1 do
      let d = (src.(j) lsr shift) land 1023 in
      dst.(c.(d)) <- src.(j);
      c.(d) <- c.(d) + 1
    done
  in
  pass 32 a b;
  pass 42 b a;
  pass 52 a b;
  let bounds = Array.init levels (fun _ -> Array.make 33 0) in
  let rec node lo hi level =
    if level >= levels then begin
      let tree = ref Leaf in
      for j = lo to hi - 1 do tree := tree_insert t.tkeys.(entry_at b j) (tget t.tvals (entry_at b j)) (entry_at b j) !tree done;
      Same !tree
    end else begin
      (* The runs of the bits of this level, at most 32: their starts in [runs], the last one's end after them. *)
      let runs = bounds.(level) and r = ref 0 and dmap = ref 0 and nmap = ref 0 and j = ref lo in
      while !j < hi do
        let f = bits_at b !j level and k = ref (!j + 1) in
        while !k < hi && bits_at b !k level = f do incr k done;
        if !k - !j = 1 then dmap := !dmap lor (1 lsl f) else nmap := !nmap lor (1 lsl f);
        runs.(!r) <- !j;
        incr r;
        j := !k
      done;
      runs.(!r) <- hi;
      let kv = Array.make (2 * popcount !dmap) Undef and hr = Array.make (popcount !dmap) 0 in
      let kids = Array.make (popcount !nmap) empty_node and i = ref 0 and m = ref 0 in
      for x = 0 to !r - 1 do
        let j = runs.(x) and k = runs.(x + 1) in
        if k - j = 1 then begin
          let e = entry_at b j in
          kv.(2 * !i) <- t.tkeys.(e);
          kv.((2 * !i) + 1) <- tget t.tvals e;
          hr.(!i) <- pack (reversed (b.(j) lsr 32)) e;
          incr i
        end else begin
          kids.(!m) <- node j k (level + 1);
          incr m
        end
      done;
      Champ { dmap = !dmap; nmap = !nmap; kv; hr; kids; ed }
    end
  in
  node 0 n 0

(* The root of a deep map as a trie: a table becomes one in place, once and for good, when a write must keep the old map or
   a probe ran too long. *)
let trie_root (keys : keys) =
  match keys.deep with
  | Deep ({ root = Table t; _ } as d) ->
    let r = to_trie t d.ded in
    d.root <- r;
    r
  | Deep d -> d.root
  | Flat -> empty_node

let rec find_node node h key level =
  match node with
  | Champ n ->
    let bit = 1 lsl frag h level in
    if n.dmap land bit <> 0 then begin
      let i = place n.dmap bit in
      if n.hr.(i) land hash_bits = h && same n.kv.(2 * i) key then n.kv.((2 * i) + 1) else Undef
    end
    else if n.nmap land bit <> 0 then find_node n.kids.(place n.nmap bit) h key (level + 1)
    else Undef
  | Same t -> tree_find key t
  | Table t -> table_find t h key

let find m h key =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let i = index keys (nvals vals) h key in
    if i < 0 then Undef else vget vals i
  | Dict { keys = { deep = Deep d; _ }; _ } -> find_node d.root h key 0
  | _ -> Undef

let length = function
  | Dict { keys = { deep = Flat; _ }; vals; _ } -> nvals vals
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

(* Room for [e] entries in a node of the owner: twice its entries, at most 32. *)
let room e = if e <= 2 then 2 else if e >= 16 then 32 else 2 * e

(* The first [n] places of [a] with a gap of [w] at [i]: in place when [mine] and there is room, else in a new array, with
   room for the owner, and no longer than needed for another map. *)
let gap mine (a : 'a array) n i w (fill : 'a) =
  if mine && n + w <= Array.length a then (Array.blit a i a (i + w) (n - i); a)
  else begin
    let b = Array.make (if mine then w * room ((n / w) + 1) else n + w) fill in
    Array.blit a 0 b 0 i;
    Array.blit a i b (i + w) (n - i);
    b
  end

(* The first [n] places of [a] without the [w] from [i]: in place when [mine], the freed places emptied for the collector;
   else a new array, made without a closure, its values moved by copies in C. *)
let cut ?(mine = false) (a : 'a array) n i w (fill : 'a) =
  if mine then (Array.blit a (i + w) a i (n - w - i); Array.fill a (n - w) w fill; a)
  else if n = w then [||]
  else begin
    let b = Array.sub a 0 (n - w) in
    if i + w < n then Array.blit a (i + w) b i (n - w - i);
    b
  end

(* The same for hashes, by loops, whose writes of integers need no barrier, where a copy in C takes one at each. *)
let gap_h mine (a : int array) n i =
  let b = if mine && n < Array.length a then a else Array.make (if mine then room (n + 1) else n + 1) 0 in
  for j = n downto i + 1 do b.(j) <- a.(j - 1) done;
  if b != a then for j = 0 to i - 1 do b.(j) <- a.(j) done;
  b

let cut_h ?(mine = false) (a : int array) n i =
  let b = if mine then a else Array.make (n - 1) 0 in
  if not mine then for j = 0 to i - 1 do b.(j) <- a.(j) done;
  for j = i to n - 2 do b.(j) <- a.(j + 1) done;
  b

(* The marks of maps: a map changes in place only the nodes of its own mark, and a new mark copies a node once. *)
let marks = ref 0

let fresh () =
  incr marks;
  !marks

(* A node of the mark [ed] with the entries and kids of [n], in arrays of its own. *)
let copy n ed =
  match n with
  | Champ n ->
    let e = popcount n.dmap and k = popcount n.nmap in
    Champ { dmap = n.dmap; nmap = n.nmap; kv = Array.sub n.kv 0 (2 * e); hr = Array.sub n.hr 0 e; kids = Array.sub n.kids 0 k; ed }
  | Same _ | Table _ -> n

(* The node of two entries of different keys whose hashes agree below [level]: inline, or a level further down, or past
   the last level the tree of equal hashes. *)
let rec pair k1 v1 r1 k2 v2 r2 level ed =
  if level >= levels then Same (tree_insert k2 v2 (r2 lsr 30) (tree_insert k1 v1 (r1 lsr 30) Leaf))
  else begin
    let f1 = frag (r1 land hash_bits) level and f2 = frag (r2 land hash_bits) level in
    if f1 = f2 then Champ { dmap = 0; nmap = 1 lsl f1; kv = [||]; hr = [||]; kids = [| pair k1 v1 r1 k2 v2 r2 (level + 1) ed |]; ed }
    else if f1 < f2 then Champ { dmap = (1 lsl f1) lor (1 lsl f2); nmap = 0; kv = [| k1; v1; k2; v2 |]; hr = [| r1; r2 |]; kids = [||]; ed }
    else Champ { dmap = (1 lsl f1) lor (1 lsl f2); nmap = 0; kv = [| k2; v2; k1; v1 |]; hr = [| r2; r1 |]; kids = [||]; ed }
  end

(* The node with [key] set to [v]: a node of the mark [ed] changes in place and is given back, another is copied with that
   mark. The mark [frozen] is a persistent write's: its nodes are never changed in place, so they share with the old node
   every array the write leaves as it was, and copy only the one it changes. [added]: set when the key is new; one flag
   for the module, as maps live on one domain (the parallel kernels never touch them), and a write never waits. *)
let frozen = 0

let rec put_node node h key v rk level ed =
  match node with
  | Champ n ->
    let bit = 1 lsl frag h level in
    let mine = ed <> frozen && n.ed = ed in
    if n.dmap land bit <> 0 then begin
      let i = place n.dmap bit in
      let r = n.hr.(i) in
      if r land hash_bits = h && same n.kv.(2 * i) key then begin
        (* A key that is there keeps its rank, so its place in the order. *)
        let c =
          if mine then node
          else if ed = frozen then Champ { n with kv = Array.sub n.kv 0 (2 * popcount n.dmap); ed }
          else copy node ed
        in
        (match c with Champ m -> m.kv.((2 * i) + 1) <- v | _ -> ());
        c
      end else begin
        (* Two keys of these 5 bits: both go a level down. *)
        added := true;
        let e = popcount n.dmap and k = popcount n.nmap and j = place n.nmap bit in
        let sub = pair n.kv.(2 * i) n.kv.((2 * i) + 1) r key v (pack h rk) (level + 1) ed in
        let kv = cut ~mine n.kv (2 * e) (2 * i) 2 Undef and hr = cut_h ~mine n.hr e i and kids = gap mine n.kids k j 1 sub in
        kids.(j) <- sub;
        if mine then (n.dmap <- n.dmap lxor bit; n.nmap <- n.nmap lor bit; n.kv <- kv; n.hr <- hr; n.kids <- kids; node)
        else Champ { dmap = n.dmap lxor bit; nmap = n.nmap lor bit; kv; hr; kids; ed }
      end
    end
    else if n.nmap land bit <> 0 then begin
      let j = place n.nmap bit in
      let kid = n.kids.(j) in
      let kid' = put_node kid h key v rk (level + 1) ed in
      if mine then begin
        if kid' != kid then n.kids.(j) <- kid';
        node
      end else if ed = frozen then begin
        let kids = Array.sub n.kids 0 (popcount n.nmap) in
        kids.(j) <- kid';
        Champ { n with kids; ed }
      end else begin
        let c = copy node ed in
        (match c with Champ m -> m.kids.(j) <- kid' | _ -> ());
        c
      end
    end else begin
      added := true;
      let e = popcount n.dmap and i = place n.dmap bit in
      let kv = gap mine n.kv (2 * e) (2 * i) 2 Undef and hr = gap_h mine n.hr e i in
      kv.(2 * i) <- key;
      kv.((2 * i) + 1) <- v;
      hr.(i) <- pack h rk;
      if mine then (n.dmap <- n.dmap lor bit; n.kv <- kv; n.hr <- hr; node)
      else Champ { dmap = n.dmap lor bit; nmap = n.nmap; kv; hr; kids = (if ed = frozen then n.kids else Array.sub n.kids 0 (popcount n.nmap)); ed }
    end
  | Same t ->
    let u = tree_insert key v rk t in
    if tree_length u > tree_length t then added := true;
    Same u
  | Table _ -> node (* a table is a root, which [trie_root] turns into a trie before a write reaches the nodes *)

let rec iter_node f = function
  | Champ n ->
    for i = 0 to popcount n.dmap - 1 do
      f (n.hr.(i) lsr 30) n.kv.(2 * i) n.kv.((2 * i) + 1)
    done;
    for j = 0 to popcount n.nmap - 1 do
      iter_node f n.kids.(j)
    done
  | Same t -> tree_iter f t
  | Table t -> for e = 0 to t.tcount - 1 do f e t.tkeys.(e) (tget t.tvals e) done

(* A new root of the mark [ed] with the [n] entries of these arrays, put in their order: a key twice keeps its first rank
   and its last value. Gives the root and the number of keys. *)
let build (hs : int array) (ks : t array) (vs : t array) (rs : int array) n ed =
  let root = Champ { dmap = 0; nmap = 0; kv = [||]; hr = [||]; kids = [||]; ed } and count = ref 0 in
  for i = 0 to n - 1 do
    added := false;
    ignore (put_node root hs.(i) ks.(i) vs.(i) rs.(i) 0 ed);
    if !added then incr count
  done;
  root, !count

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

let deep root size next ded =
  Dict { keys = { ks = [||]; hs = [||]; used = whole; deep = Deep { root; size; next; order = no_order; ded } }; vals = no_vals; d_owned = true }

(* The values and one more: a float keeps an F store, or makes one of an empty map. *)
let vappend s x =
  match s, x with
  | F d, Float f ->
    let n = Float.Array.length d in
    let e = Float.Array.make (n + 1) f in
    Float.Array.blit d 0 e 0 n;
    F e
  | V [||], Float f -> F (Float.Array.make 1 f)
  | V d, _ -> V (append_v d x)
  | s, _ -> V (append (vals_array s) x)

(* A block of [n] keys and a new one: one more key, or past [width] a deep map. *)
let add_new ?(owned = true) keys vals n h key v =
  if n < width then Dict { keys = grow keys n key h; vals = vappend vals v; d_owned = owned }
  else begin
    let hs = with_last keys.hs n h and ks = with_last keys.ks n key and vs = append (vals_array vals) v and ed = fresh () in
    let root = match table_of hs ks vs (n + 1) with Some t -> Table t | None -> fst (build hs ks vs (Array.init (n + 1) Fun.id) (n + 1) ed) in
    deep root (n + 1) (n + 1) ed
  end

(* Ranks fit in 33 bits beside 30 of hash, and [next] only grows: a map that adds and drops keys for long, a cache of a
   server, renumbers its ranks in its order when [next] reaches this, once in four billion keys. A ref, for tests. *)
let rank_limit = ref (1 lsl 32)

let renumber root size next ed =
  let o = deep_items root size next in
  let ks = Array.init size (fun i -> o.(2 * i)) and vs = Array.init size (fun i -> o.((2 * i) + 1)) in
  fst (build (Array.map hash ks) ks vs (Array.init size Fun.id) size ed)

(* The map with [key] set to [v], a new one: a key that is there keeps its place, and the values of a copied block are in
   both maps. [m] never changes: natives give new values. *)
let put m h key v =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    (* Both maps hold these values now: neither is owned, so a write to either copies it first and marks its values. *)
    ignore (share m);
    let n = nvals vals in
    let i = index keys n h key in
    if i >= 0 then begin
      let c = Dict { keys; vals = (match vals with F d -> F (Float.Array.copy d) | s -> V (Array.copy (vals_array s))); d_owned = true } in
      vset c i v;
      (match c with Dict r -> r.d_owned <- false | _ -> ());
      c
    end else add_new ~owned:false keys vals n h key v
  | Dict { keys = { deep = Deep d; _ } as keys; _ } ->
    (* Both maps hold these nodes now: the old one must copy before it writes. *)
    ignore (share m);
    added := false;
    let root = put_node (trie_root keys) h key v d.next 0 frozen and ed = fresh () in
    if not !added then deep root d.size d.next ed
    else if d.next + 1 >= !rank_limit then deep (renumber root (d.size + 1) (d.next + 1) ed) (d.size + 1) (d.size + 1) ed
    else deep root (d.size + 1) (d.next + 1) ed
  | _ -> m

(* The same for a map that nothing else holds, a write to a variable: it changes in place, or gives the map that takes its
   place, and its values move without being marked as shared. *)
let put_owned m h key v =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let n = nvals vals in
    let i = index keys n h key in
    if i >= 0 then begin
      vset m i v;
      m
    end else add_new keys vals n h key v
  | Dict { keys = { deep = Deep d; _ } as keys; _ } ->
    added := false;
    (match d.root with
     | Table t when table_put t h key v -> ()
     | _ -> d.root <- put_node (trie_root keys) h key v d.next 0 d.ded);
    if !added then begin
      d.size <- d.size + 1;
      d.next <- d.next + 1;
      if d.next >= !rank_limit then begin
        d.root <- renumber d.root d.size d.next d.ded;
        d.next <- d.size
      end
    end;
    d.order <- no_order;
    m
  | _ -> m

(* [put_owned] for a key that a map of one block lacks. *)
let add_absent m h key v =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } -> add_new keys vals (nvals vals) h key v
  | _ -> put_owned m h key v

(* A copy of a map that someone else holds too: a deep map gets a new mark, so that its writes copy the nodes first. *)
let own_copy m =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals = F d; _ } -> Dict { keys; vals = F (Float.Array.copy d); d_owned = true }
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let d = vals_array vals in
    Array.iter (fun x -> ignore (share x)) d;
    Dict { keys; vals = V (Array.copy d); d_owned = true }
  | Dict { keys = { deep = Deep d; _ } as keys; _ } ->
    Dict { keys = { ks = [||]; hs = [||]; used = whole; deep = Deep { root = trie_root keys; size = d.size; next = d.next; order = d.order; ded = fresh () } }; vals = no_vals; d_owned = true }
  | _ -> m

(* What a node is once a key left it: nothing, one entry that its parent takes inline, or more. *)
type left = Gone | One of t * t * int | More

let left node h =
  match node with
  | Champ { dmap = 0; nmap = 0; _ } | Same Leaf -> Gone
  | Champ n when n.nmap = 0 && n.dmap land (n.dmap - 1) = 0 -> One (n.kv.(0), n.kv.(1), n.hr.(0))
  | Same (Node { l = Leaf; r = Leaf; k; v; hr; _ }) -> One (k, v, pack h (hr lsr 6))
  | _ -> More

(* The node without [key], or the same node. A drop is persistent: its nodes are frozen, and share with the old ones the
   arrays it leaves as they were. A kid left with one entry comes back inline, so the map stays as CHAMP keeps it: no node
   holds a lone key below it. *)
let rec drop_node node h key level =
  match node with
  | Champ n ->
    let bit = 1 lsl frag h level in
    if n.dmap land bit <> 0 then begin
      let i = place n.dmap bit in
      if n.hr.(i) land hash_bits = h && same n.kv.(2 * i) key then begin
        let e = popcount n.dmap in
        Champ { n with dmap = n.dmap lxor bit; kv = cut n.kv (2 * e) (2 * i) 2 Undef; hr = cut_h n.hr e i; ed = frozen }
      end
      else node
    end
    else if n.nmap land bit <> 0 then begin
      let j = place n.nmap bit in
      let kid = n.kids.(j) in
      let kid' = drop_node kid h key (level + 1) in
      if kid' == kid then node
      else begin
        let e = popcount n.dmap and k = popcount n.nmap in
        match left kid' h with
        | Gone -> Champ { n with nmap = n.nmap lxor bit; kids = cut n.kids k j 1 kid'; ed = frozen }
        | One (k', v', r') ->
          let i = place n.dmap bit in
          let kv = gap false n.kv (2 * e) (2 * i) 2 k' and hr = gap_h false n.hr e i in
          hr.(i) <- r';
          kv.((2 * i) + 1) <- v';
          Champ { dmap = n.dmap lor bit; nmap = n.nmap lxor bit; kv; hr; kids = cut n.kids k j 1 kid'; ed = frozen }
        | More ->
          let kids = Array.sub n.kids 0 k in
          kids.(j) <- kid';
          Champ { n with kids; ed = frozen }
      end
    end
    else node
  | Same t ->
    let u = tree_delete key t in
    if tree_length u = tree_length t then node else Same u
  | Table _ -> node

let drop m h key =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } ->
    let n = nvals vals in
    let i = index keys n h key in
    if i < 0 then m
    else begin
      ignore (share m);
      let rest = cut (vals_array vals) n i 1 Undef in
      Dict { keys = { ks = cut keys.ks n i 1 Undef; hs = cut_h keys.hs n i; used = whole; deep = Flat };
             vals = (match vals with F _ -> vals_of rest | _ -> V rest); d_owned = false }
    end
  | Dict { keys = { deep = Deep d; _ } as keys; _ } ->
    let root = drop_node (trie_root keys) h key 0 in
    if root != d.root then ignore (share m);
    if root == d.root then m else deep root (d.size - 1) d.next (fresh ())
  | _ -> m

let items m =
  match m with
  | Dict { keys = { deep = Flat; _ } as keys; vals; _ } -> Array.init (2 * nvals vals) (fun j -> if j land 1 = 0 then keys.ks.(j / 2) else vget vals (j / 2))
  | Dict { keys = { deep = Deep d; _ }; _ } when d.order != no_order -> d.order
  | Dict { keys = { deep = Deep d; _ }; _ } ->
    let o = deep_items d.root d.size d.next in
    d.order <- o;
    o
  | _ -> [||]

(* Two keys written the same way: the keys of a map can be shared with another only then, as 1 and 1.0 are one key but don't
   print alike. *)
let alike a b = match a, b with Text x, Text y -> String.equal x y | Int x, Int y -> x = y | _ -> false

(* The keys k1 v1 k2 v2..., already checked: a later key replaces the value and keeps the place. With the same keys in the same
   order as [like], the map shares them. *)
let of_items ?(like = no_keys) (a : t array) =
  let n = Array.length a / 2 in
  let rec fits i = i = n || (alike like.ks.(i) a.(2 * i) && fits (i + 1)) in
  if n > 0 && is_whole like && n = Array.length like.ks && fits 0 then record like (Array.init n (fun i -> a.((2 * i) + 1)))
  else if n <= width then begin
    (* One block: a key twice keeps its first place and its last value. *)
    let kk = Array.make n Undef and kh = Array.make n 0 and kv = Array.make n Undef and m = ref 0 in
    for i = 0 to n - 1 do
      let k = a.(2 * i) in
      let h = hash k in
      let rec at j = if j = !m then -1 else if kh.(j) = h && same kk.(j) k then j else at (j + 1) in
      let j = at 0 in
      if j >= 0 then kv.(j) <- a.((2 * i) + 1)
      else begin
        kk.(!m) <- k;
        kh.(!m) <- h;
        kv.(!m) <- a.((2 * i) + 1);
        incr m
      end
    done;
    let m = !m in
    record { ks = Array.sub kk 0 m; hs = Array.sub kh 0 m; used = whole; deep = Flat } (Array.sub kv 0 m)
  end else begin
    let hs = Array.init n (fun i -> hash a.(2 * i)) and ks = Array.init n (fun i -> a.(2 * i)) and vs = Array.init n (fun i -> a.((2 * i) + 1)) in
    let ed = fresh () in
    match table_of hs ks vs n with
    | Some t -> deep (Table t) t.tcount t.tcount ed
    | None ->
      let root, count = build hs ks vs (Array.init n Fun.id) n ed in
      deep root count n ed
  end

let keys_of_map = function Dict { keys = { deep = Flat; _ } as keys; _ } when is_whole keys -> keys | _ -> no_keys

(* Whole keys of [n] and one more, for a name written in the code, which the maps that come through share. *)
let extend keys n key h = { ks = with_last keys.ks n key; hs = with_last keys.hs n h; used = whole; deep = Flat }
