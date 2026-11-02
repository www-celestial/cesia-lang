open Types

let array_arg ctx name v =
  match v with
  | Array a -> a
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

let size a = a.rows * a.cols
let is_missing = function Missing -> true | _ -> false
let record ctx names fields = Struct { shape = Value.shape_of ctx.w names; fields; r_owned = true }

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

let mix x =
  let h = x * 0x9E3779B97F4A7C1 in
  h lxor (h lsr 31)

let hash_text s =
  let h = ref 0 in
  String.iter (fun c -> h := (!h * 31) + Char.code c) s;
  mix !h

(* A float that holds an integer hashes like it: they are the same key. *)
let hash_float x =
  if Float.is_integer x && Float.abs x < 4e18 then mix (int_of_float x)
  else mix (Int64.to_int (Int64.bits_of_float x))

let hash_value = function
  | Int i -> mix i
  | Float x -> hash_float x
  | Text s -> hash_text s
  | True -> 1
  | False -> 2
  | _ -> 0

let hasher a =
  match a.store with
  | I d -> fun k -> mix d.(k)
  | F d -> fun k -> hash_float (Float.Array.get d k)
  | V d -> fun k -> hash_value d.(k)

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
  | F d -> Float.Array.iter (fun x -> if Float.is_nan x then ignore (Dict.find ctx (Float x) Leaf)) d
  | V d -> Array.iter (fun v -> ignore (Dict.find ctx v Leaf)) d

(* A cell of a key of several columns may also be missing or a boolean. Anything else has no useful hash. *)
let check_cells ctx a =
  match a.store with
  | V d -> Array.iter (function Missing | True | False -> () | v -> ignore (Dict.find ctx v Leaf)) d
  | _ -> ()

(* Open addressing: a slot holds a group, or -1, and a group the first position of its key. *)
type index = { mutable slots : int array; mutable groups : int; mutable firsts : int array }

let grow ctx t hash =
  let size = 2 * Array.length t.slots in
  let slots = Runtime.alloc_ints ctx size (-1) in
  for g = 0 to t.groups - 1 do
    let i = ref (hash t.firsts.(g) land (size - 1)) in
    while slots.(!i) >= 0 do i := (!i + 1) land (size - 1) done;
    slots.(!i) <- g
  done;
  t.slots <- slots;
  t.firsts <- Array.append t.firsts (Array.make (Array.length t.firsts) 0)

(* The group of each position, numbered by first appearance. *)
let factorize ctx n hash equal =
  let t = { slots = Array.make 1024 (-1); groups = 0; firsts = Array.make 512 0 } in
  let ids = Runtime.alloc_ints ctx n 0 in
  for k = 0 to n - 1 do
    let mask = Array.length t.slots - 1 in
    let i = ref (hash k land mask) in
    let g = ref t.slots.(!i) in
    while !g >= 0 && not (equal t.firsts.(!g) k) do
      i := (!i + 1) land mask;
      g := t.slots.(!i)
    done;
    if !g >= 0 then ids.(k) <- !g
    else begin
      t.slots.(!i) <- t.groups;
      t.firsts.(t.groups) <- k;
      ids.(k) <- t.groups;
      t.groups <- t.groups + 1;
      if 2 * t.groups >= Array.length t.slots then grow ctx t hash
    end
  done;
  t, ids

let lookup t hash equal k =
  let mask = Array.length t.slots - 1 in
  let i = ref (hash k land mask) in
  let g = ref t.slots.(!i) in
  while !g >= 0 && not (equal t.firsts.(!g) k) do
    i := (!i + 1) land mask;
    g := t.slots.(!i)
  done;
  !g

let int_list d = if Array.length d = 0 then Arrays.list [||] else Arrays.of_ints 1 (Array.length d) d

(* groups(keys): {ids, count, firsts} for rows that share the values of these columns. One column follows the rules of a
   dictionary's keys. For several, the pair of the groups so far and of the next column gets a new group: a group stays
   below the number of rows, so that a pair can't overflow. *)
let groups ctx (a : t array) =
  let cols = column_list ctx "groups" a.(0) in
  let n = if Array.length cols = 0 then 0 else size cols.(0) in
  Array.iter (fun c -> Runtime.build ctx (size c)) cols;
  let of_column c = factorize ctx n (hasher c) (same c c) in
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
           factorize ctx n (fun k -> mix pairs.(k)) (fun i j -> pairs.(i) = pairs.(j)))
        (of_column c) rest
  in
  record ctx [| "ids"; "count"; "firsts" |]
    [| int_list (Array.map succ ids); Int t.groups; int_list (Array.init t.groups (fun g -> t.firsts.(g) + 1)) |]

(* split(g, xs): the values of xs in each group, in order, without the missing ones. *)
let split ctx (a : t array) =
  let field g name =
    match g with
    | Struct r when Value.field_index r.shape name >= 0 -> r.fields.(Value.field_index r.shape name)
    | v -> Runtime.fail ctx Type (Messages.need_groups (Value.describe v))
  in
  let ids = ints ctx "split" (field a.(0) "ids") and count = Arrays.whole_index ctx (field a.(0) "count") in
  let x = array_arg ctx "split" a.(1) in
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

(* pick(ks, xs): the values at these positions. Position 0 gives missing: an unmatched row of a left join. *)
let pick ctx (a : t array) =
  let ks = ints ctx "pick" a.(0) and x = array_arg ctx "pick" a.(1) in
  let n = size x and k = Array.length ks in
  Runtime.build ctx k;
  Array.iter (fun i -> if i < 0 || i > n then Runtime.fail ctx Index (Messages.index_outside i n)) ks;
  if k = 0 then Arrays.list [||]
  else if Array.mem 0 ks then Arrays.list (Array.map (fun i -> if i = 0 then Missing else Value.share (Value.elt x (i - 1))) ks)
  else Arrays.pick ctx x (Array.map pred ks) 1 k

(* join(ys, xs, keep): {left, right}, the positions in ys and xs of the rows that match, in the order of ys then xs. With
   keep, a row of ys that matches nothing stays, with position 0 in xs. *)
let join ctx (a : t array) =
  let ys = array_arg ctx "join" a.(0) and xs = array_arg ctx "join" a.(1) and keep = a.(2) = True in
  let n = size xs and m = size ys in
  Runtime.build ctx (n + m);
  check_keys ctx xs;
  check_keys ctx ys;
  let t, ids = factorize ctx n (hasher xs) (same xs xs) in
  let starts = Array.make (t.groups + 1) 0 in
  Array.iter (fun g -> starts.(g + 1) <- starts.(g + 1) + 1) ids;
  for g = 1 to t.groups do starts.(g) <- starts.(g) + starts.(g - 1) done;
  let members = Array.make n 0 and cursor = Array.copy starts in
  Array.iteri
    (fun k g ->
       members.(cursor.(g)) <- k;
       cursor.(g) <- cursor.(g) + 1)
    ids;
  let hash_y = hasher ys and cross = same xs ys in
  let found = Array.make m (-1) in
  Par.ranges m (fun lo hi -> for k = lo to hi - 1 do found.(k) <- lookup t hash_y cross k done);
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
  record ctx [| "left"; "right" |] [| int_list left; int_list right |]

let positions ctx (a : t array) =
  let m = array_arg ctx "positions" a.(0) in
  int_list (Array.map succ (Arrays.positions ctx (size m) (Arrays.Mask m)))

let present ctx (a : t array) =
  let x = array_arg ctx "present" a.(0) in
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
  let s = Native.text_arg ctx "csv" a.(0) and separator = Native.text_arg ctx "csv" a.(1) in
  Arrays.list (Array.map texts (csv_rows ctx s separator))

(* read_csv(s, separator): {names, columns}. An empty cell is missing, and a column of numbers takes its typed storage. *)
let read_csv ctx (a : t array) =
  let s = Native.text_arg ctx "read_csv" a.(0) and separator = Native.text_arg ctx "read_csv" a.(1) in
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
  record ctx [| "names"; "columns" |] [| texts names; Arrays.list (Array.init (Array.length names) column) |]

let kind (a : t array) =
  match a.(0) with
  | Array { store = I _; _ } -> Text "int"
  | Array { store = F _; _ } -> Text "float"
  | _ -> Text "value"

let natives =
  [ "kind", Native.nat "kind" 1 1 (fun _ a -> kind a);
    "cores", Native.nat "cores" 0 0 (fun _ _ -> Int (Par.cores ()));
    "groups", Native.nat "groups" 1 1 groups;
    "split", Native.nat "split" 2 2 split;
    "pick", Native.nat "pick" 2 2 pick;
    "join", Native.nat "join" 3 3 join;
    "positions", Native.nat "positions" 1 1 positions;
    "present", Native.nat "present" 1 1 present;
    "csv", Native.nat "csv" 2 2 csv;
    "read_csv", Native.nat "read_csv" 2 2 read_csv ]
