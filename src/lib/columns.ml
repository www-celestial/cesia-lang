open Types

let array_arg ctx name v =
  match v with
  | Array a -> Value.trim a
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

let size a = a.rows * a.cols
let is_missing = function Missing -> true | _ -> false
let record (_ : ctx) names fields = Trie.record (Trie.names names) fields

(* A column of positions or counts. *)
let ints ctx name v =
  let a = array_arg ctx name v in
  match a.store with
  | I d -> d
  | _ -> Array.init (size a) (fun k -> Arrays.whole_index ctx (Value.elt a k))

(* The columns of a list of columns, all of one length. *)
let column_list ctx name v =
  let a = array_arg ctx name v in
  let cols = Array.init (size a) (fun k -> array_arg ctx name (Value.elt a k)) in
  Array.iter
    (fun c -> if size c <> size cols.(0) then Runtime.fail ctx Type (Messages.column_sizes (size c) (size cols.(0))))
    cols;
  cols

(* The hash of the maps, with its seed drawn at each run: no input can choose keys that fall together. Equal keys hash
   alike, 1 and 1.0 too, as in a map. An integer past 2^53 is the same key as the float it rounds to, which up to 1,024
   integers share: it hashes as that float only when [wide], a float past 2^53 among the keys; otherwise by all its bits. *)
let[@inline] hash_int wide x =
  if wide || (x < 1 lsl 53 && x > -(1 lsl 53)) then Trie.hash_int x
  else Trie.hash_int (Trie.hash_int (x asr 11) lxor (x land 2047))

let hash_value wide = function
  | Int i -> hash_int wide i
  | Float x -> Trie.hash_float x
  | Text s -> Trie.hash_text s
  | True -> 1
  | False -> 2
  | _ -> 0

let hasher wide a =
  match a.store with
  | I d -> fun k -> hash_int wide d.(k)
  | F d -> fun k -> Trie.hash_float (Float.Array.get d k)
  | V d -> fun k -> hash_value wide d.(k)

let wide a =
  match a.store with
  | I _ -> false
  | F d -> Float.Array.exists (fun x -> Float.abs x >= 0x1p53) d
  | V d -> Array.exists (function Float x -> Float.abs x >= 0x1p53 | _ -> false) d

let same_value a b =
  match a, b with
  | (Int _ | Float _ | Text _), (Int _ | Float _ | Text _) -> Dict.compare_keys a b = 0
  | Missing, Missing | True, True | False, False -> true
  | _ -> false

(* Is position i of [a] the same key as position j of [b]? *)
let same a b =
  match a.store, b.store with
  | I x, I y -> fun i j -> x.(i) = y.(j)
  | F x, F y -> fun i j -> Float.compare (Float.Array.get x i) (Float.Array.get y j) = 0
  | _ -> fun i j -> same_value (Value.elt a i) (Value.elt b j)

(* Keys of a dictionary, so that a table refuses what a dictionary refuses. *)
let check_keys ctx a =
  match a.store with
  | I _ -> ()
  | F d -> Float.Array.iter (fun x -> if Float.is_nan x then Dict.check ctx (Float x)) d
  | V d -> Array.iter (Dict.check ctx) d

(* A cell of a key of several columns may also be missing or a boolean. Anything else has no useful hash. *)
let check_cells ctx a =
  match a.store with
  | V d -> Array.iter (function Missing | True | False -> () | v -> Dict.check ctx v) d
  | _ -> ()

(* Open addressing: a slot holds -1, or a group below the hash of its key (30 bits above 32), so that a probe compares
   keys only when their hashes agree. A group holds the first position of its key and, for integers, the key itself, so
   that a probe reads no column. Groups are placed in their order, so that of the groups whose keys equal a key, the first
   one is found. *)
type index = { mutable slots : int array; mutable groups : int; mutable firsts : int array; mutable keys : int array }

let group_of s = s land 0xFFFF_FFFF

(* An index and the ids of n positions. A group fits in 32 bits: four billion rows. *)
let index ctx n keys =
  if n >= 1 lsl 32 then Runtime.limit "memory" ctx.site;
  { slots = Array.make 1024 (-1); groups = 0; firsts = Array.make 512 0; keys = Array.make keys 0 }, Runtime.alloc_ints ctx n 0

let doubled a =
  let b = Array.make (2 * Array.length a) 0 in
  Array.blit a 0 b 0 (Array.length a);
  b

(* Twice the slots, with the hashes they hold. From a free slot on, so that groups of one hash come in their order. *)
let grow ctx t =
  let old = t.slots in
  let n = Array.length old in
  let slots = Runtime.alloc_ints ctx (2 * n) (-1) in
  let free = ref 0 in
  while old.(!free) >= 0 do incr free done;
  for j = 1 to n do
    let s = old.((!free + j) land (n - 1)) in
    if s >= 0 then begin
      let i = ref ((s lsr 32) land ((2 * n) - 1)) in
      while slots.(!i) >= 0 do i := (!i + 1) land ((2 * n) - 1) done;
      slots.(!i) <- s
    end
  done;
  t.slots <- slots;
  t.firsts <- doubled t.firsts;
  t.keys <- doubled t.keys

(* Position k, of hash h, at slot i: the group there, or a new one in that free slot. *)
let[@inline] place ctx t ids k h i =
  let s = t.slots.(i) in
  if s >= 0 then ids.(k) <- group_of s
  else begin
    t.slots.(i) <- (h lsl 32) lor t.groups;
    t.firsts.(t.groups) <- k;
    ids.(k) <- t.groups;
    t.groups <- t.groups + 1;
    if 2 * t.groups >= Array.length t.slots then grow ctx t
  end

(* The slot of the group of position k, of hash h, or of the free slot where it goes. *)
let[@inline] probe t equal h k =
  let mask = Array.length t.slots - 1 in
  let i = ref (h land mask) in
  let s = ref t.slots.(!i) in
  while !s >= 0 && not (!s lsr 32 = h && equal t.firsts.(group_of !s) k) do
    i := (!i + 1) land mask;
    s := t.slots.(!i)
  done;
  !i

(* The group of each position, numbered by first appearance. *)
let factorize ctx n hash equal =
  let t, ids = index ctx n 0 in
  for k = 0 to n - 1 do
    let h = hash k in
    place ctx t ids k h (probe t equal h k)
  done;
  t, ids

(* [probe] in an index of integers, for the integer x: no call per position. *)
let[@inline] probe_int t h x =
  let mask = Array.length t.slots - 1 in
  let i = ref (h land mask) in
  while t.slots.(!i) >= 0 && not (t.slots.(!i) lsr 32 = h && t.keys.(group_of t.slots.(!i)) = x) do
    i := (!i + 1) land mask
  done;
  !i

let factorize_ints ctx wide (d : int array) =
  let t, ids = index ctx (Array.length d) 512 in
  for k = 0 to Array.length d - 1 do
    let x = d.(k) in
    let h = hash_int wide x in
    let i = probe_int t h x in
    if t.slots.(i) < 0 then t.keys.(t.groups) <- x;
    place ctx t ids k h i
  done;
  t, ids

let lookup t hash equal k =
  let s = t.slots.(probe t equal (hash k) k) in
  if s >= 0 then group_of s else -1

let int_list d = if Array.length d = 0 then Arrays.list [||] else Arrays.of_ints 1 (Array.length d) d

(* Groups(keys): {Ids, Count, Firsts} for rows that share the values of these columns. One column follows the rules of a
   dictionary's keys. For several, the pair of the groups so far and of the next column gets a new group: a group stays
   below the number of rows, so that a pair can't overflow. *)
let groups ctx (a : t array) =
  let cols = column_list ctx "Groups" a.(0) in
  let n = if Array.length cols = 0 then 0 else size cols.(0) in
  Array.iter (fun c -> Runtime.build ctx (size c)) cols;
  let of_column c =
    match c.store with
    | I d -> factorize_ints ctx false d
    | F _ -> factorize ctx n (hasher false c) (same c c)
    | V _ -> factorize ctx n (hasher (wide c) c) (same c c)
  in
  let t, ids =
    match Array.to_list cols with
    | [] -> factorize ctx 0 (fun _ -> 0) (fun _ _ -> true)
    | [ c ] ->
      check_keys ctx c;
      of_column c
    | c :: rest ->
      Array.iter (check_cells ctx) cols;
      List.fold_left
        (fun (_, ids) c ->
           let t, own = of_column c in
           let pairs = Array.mapi (fun k id -> (ids.(k) * t.groups) + id) own in
           factorize_ints ctx false pairs)
        (of_column c) rest
  in
  record ctx [| "Ids"; "Count"; "Firsts" |]
    [| int_list (Array.map succ ids); Int t.groups; int_list (Array.init t.groups (fun g -> t.firsts.(g) + 1)) |]

(* Split(g, xs): the values of xs in each group, in order, without the missing ones. *)
let split ctx (a : t array) =
  let field g name =
    match g with
    | Dict _ when Trie.find g (Trie.hash (Text name)) (Text name) != Undef -> Trie.find g (Trie.hash (Text name)) (Text name)
    | v -> Runtime.fail ctx Type (Messages.need_groups (Value.describe v))
  in
  let ids = ints ctx "Split" (field a.(0) "Ids") and count = Arrays.whole_index ctx (field a.(0) "Count") in
  let x = array_arg ctx "Split" a.(1) in
  let n = size x in
  if Array.length ids <> n then Runtime.fail ctx Type (Messages.column_sizes (Array.length ids) n);
  if count < 0 || count > n || Array.exists (fun id -> id < 1 || id > count) ids then
    Runtime.fail ctx Type (Messages.need_groups (Value.describe a.(0)));
  Runtime.build ctx (n + count);
  let keep k = match x.store with V d -> not (is_missing d.(k)) | _ -> true in
  let sizes = Array.make count 0 in
  for k = 0 to n - 1 do
    if keep k then sizes.(ids.(k) - 1) <- sizes.(ids.(k) - 1) + 1
  done;
  let used = Array.make count 0 in
  let next k =
    let g = ids.(k) - 1 in
    used.(g) <- used.(g) + 1;
    g, used.(g) - 1
  in
  let parts =
    match x.store with
    | F d ->
      let out = Array.map (fun s -> Float.Array.create s) sizes in
      for k = 0 to n - 1 do
        let g, at = next k in
        Float.Array.set out.(g) at (Float.Array.get d k)
      done;
      Array.mapi (fun g p -> if sizes.(g) = 0 then Arrays.list [||] else Arrays.of_float 1 sizes.(g) p) out
    | I d ->
      let out = Array.map (fun s -> Array.make s 0) sizes in
      for k = 0 to n - 1 do
        let g, at = next k in
        out.(g).(at) <- d.(k)
      done;
      Array.map int_list out
    | V d ->
      let out = Array.map (fun s -> Array.make s Missing) sizes in
      for k = 0 to n - 1 do
        if keep k then begin
          let g, at = next k in
          out.(g).(at) <- Value.share d.(k)
        end
      done;
      Array.map Arrays.list out
  in
  Arrays.list parts

(* Pick(ks, xs): the values at these positions. Position 0 gives missing: an unmatched row of a left join. *)
let pick ctx (a : t array) =
  let ks = ints ctx "Pick" a.(0) and x = array_arg ctx "Pick" a.(1) in
  let n = size x and k = Array.length ks in
  Runtime.build ctx k;
  Array.iter (fun i -> if i < 0 || i > n then Runtime.fail ctx Index (Messages.index_outside i n)) ks;
  if k = 0 then Arrays.list [||]
  else if Array.mem 0 ks then Arrays.list (Array.map (fun i -> if i = 0 then Missing else Value.share (Value.elt x (i - 1))) ks)
  else Arrays.pick ctx x (Array.map pred ks) 1 k

(* Join(ys, xs, keep): {Left, Right}, the positions in ys and xs of the rows that match, in the order of ys then xs. With
   keep, a row of ys that matches nothing stays, with position 0 in xs. *)
let join ctx (a : t array) =
  let ys = array_arg ctx "Join" a.(0) and xs = array_arg ctx "Join" a.(1) and keep = a.(2) = True in
  let n = size xs and m = size ys in
  Runtime.build ctx (n + m);
  check_keys ctx xs;
  check_keys ctx ys;
  let wide = wide xs || wide ys in
  let t, ids = match xs.store with I d -> factorize_ints ctx wide d | _ -> factorize ctx n (hasher wide xs) (same xs xs) in
  let starts = Array.make (t.groups + 1) 0 in
  Array.iter (fun g -> starts.(g + 1) <- starts.(g + 1) + 1) ids;
  for g = 1 to t.groups do starts.(g) <- starts.(g) + starts.(g - 1) done;
  let members = Array.make n 0 and cursor = Array.copy starts in
  Array.iteri
    (fun k g ->
       members.(cursor.(g)) <- k;
       cursor.(g) <- cursor.(g) + 1)
    ids;
  let hash_y = hasher wide ys and cross = same xs ys in
  let found = Array.make m (-1) in
  (match xs.store, ys.store with
   | I _, I y ->
     Par.ranges m (fun lo hi ->
         for k = lo to hi - 1 do
           let s = t.slots.(probe_int t (hash_int false y.(k)) y.(k)) in
           found.(k) <- (if s >= 0 then group_of s else -1)
         done)
   | _ -> Par.ranges m (fun lo hi -> for k = lo to hi - 1 do found.(k) <- lookup t hash_y cross k done));
  let total = ref 0 in
  Array.iter (fun g -> total := !total + if g >= 0 then starts.(g + 1) - starts.(g) else if keep then 1 else 0) found;
  Runtime.build ctx (2 * !total);
  let left = Array.make !total 0 and right = Array.make !total 0 and used = ref 0 in
  let add l r =
    left.(!used) <- l + 1;
    right.(!used) <- r;
    incr used
  in
  Array.iteri
    (fun k g ->
       if g < 0 then (if keep then add k 0)
       else
         for at = starts.(g) to starts.(g + 1) - 1 do
           add k (members.(at) + 1)
         done)
    found;
  record ctx [| "Left"; "Right" |] [| int_list left; int_list right |]

let positions ctx (a : t array) =
  let m = array_arg ctx "Positions" a.(0) in
  int_list (Array.map succ (Arrays.positions ctx (size m) (Arrays.Mask m)))

let present ctx (a : t array) =
  let x = array_arg ctx "Present" a.(0) in
  match x.store with
  | F _ | I _ -> a.(0)
  | V d ->
    Runtime.build ctx (Array.length d);
    Arrays.list (Array.of_seq (Seq.filter_map (fun v -> if is_missing v then None else Some (Value.share v)) (Array.to_seq d)))

(* RFC 4180: quotes around a field, doubled inside. Gives the rows as arrays of fields. *)
let csv_rows ctx s separator =
  Runtime.pay_bytes ctx (String.length s);
  Runtime.build ctx ((String.length s / 8) + 1);
  let n = String.length s in
  let sep = if String.length separator = 1 then Char.code separator.[0] else -1 in
  let special c = c = '"' || c = '\n' || c = '\r' || Char.code c = sep in
  let rows = Dynarray.create () and row = Dynarray.create () and field = Buffer.create 64 in
  let end_field () =
    Dynarray.add_last row (Buffer.contents field);
    Buffer.clear field
  in
  let end_row () =
    end_field ();
    Dynarray.add_last rows (Dynarray.to_array row);
    Dynarray.clear row
  in
  let quoted = ref false and i = ref 0 in
  while !i < n do
    let c = s.[!i] in
    if !quoted then begin
      if c <> '"' then begin
        let stop = Option.value (String.index_from_opt s !i '"') ~default:n in
        Buffer.add_substring field s !i (stop - !i);
        i := stop
      end
      else if !i + 1 < n && s.[!i + 1] = '"' then begin
        Buffer.add_char field '"';
        i := !i + 2
      end
      else begin
        quoted := false;
        incr i
      end
    end
    else if c = '"' then begin
      quoted := true;
      incr i
    end
    else if Char.code c = sep then begin
      end_field ();
      incr i
    end
    else if c = '\n' || c = '\r' then begin
      if c = '\r' && !i + 1 < n && s.[!i + 1] = '\n' then incr i;
      end_row ();
      incr i
    end
    else begin
      let start = !i in
      while !i < n && not (special s.[!i]) do incr i done;
      Buffer.add_substring field s start (!i - start)
    end
  done;
  if Buffer.length field > 0 || Dynarray.length row > 0 then end_row ();
  Dynarray.to_array rows

let texts row = Arrays.list (Array.map (fun s -> Text s) row)

let csv ctx (a : t array) =
  let s = Native.text_arg ctx "Csv" a.(0) and separator = Native.text_arg ctx "Csv" a.(1) in
  Arrays.list (Array.map texts (csv_rows ctx s separator))

(* ReadCsv(s, separator): {Names, Columns}. An empty cell is missing, and a column of numbers takes its typed storage. *)
let read_csv ctx (a : t array) =
  let s = Native.text_arg ctx "ReadCsv" a.(0) and separator = Native.text_arg ctx "ReadCsv" a.(1) in
  let rows = csv_rows ctx s separator in
  let names = if Array.length rows = 0 then [||] else rows.(0) in
  let body = max 0 (Array.length rows - 1) in
  let cell k row =
    if k >= Array.length row || row.(k) = "" then Missing
    else
      match Native.number row.(k) with
      | Missing -> Text row.(k)
      | v -> v
  in
  let column k = Arrays.list (Array.init body (fun r -> cell k rows.(r + 1))) in
  record ctx [| "Names"; "Columns" |] [| texts names; Arrays.list (Array.init (Array.length names) column) |]

let kind (a : t array) =
  match a.(0) with
  | Array { store = I _; _ } -> Text "int"
  | Array { store = F _; _ } -> Text "float"
  | _ -> Text "value"

let natives =
  [ "Kind", Native.nat "Kind" 1 1 (fun _ a -> kind a);
    "Cores", Native.nat "Cores" 0 0 (fun _ _ -> Int (Par.cores ()));
    "Groups", Native.nat "Groups" 1 1 groups;
    "Split", Native.nat "Split" 2 2 split;
    "Pick", Native.nat "Pick" 2 2 pick;
    "Join", Native.nat "Join" 3 3 join;
    "Positions", Native.nat "Positions" 1 1 positions;
    "Present", Native.nat "Present" 1 1 present;
    "Csv", Native.nat "Csv" 2 2 csv;
    "ReadCsv", Native.nat "ReadCsv" 2 2 read_csv ]
