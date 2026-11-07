open Types

let nat = Native.nat
let text_arg = Native.text_arg

let items ctx name v =
  match v with
  | Array a -> a
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

(* The cells of a list and their count, for the price of copying them all. *)
let cells ctx name v =
  let a = items ctx name v in
  let n = a.rows * a.cols in
  Runtime.build ctx n;
  a, n

let elements ctx name v =
  let a, n = cells ctx name v in
  Array.init n (fun k -> Value.share (Value.elt a k))

(* A list with a value at its end. A list keeps free cells behind its last one, doubled when they run out, so a loop of
   pushes stays linear. The new list shares the store: the old one still ends where it did, and it stops being the tip, so
   a second push from it copies instead of taking the same cell. Sharing a store ends ownership: a write copies. *)
let push ctx x a =
  let n = a.rows * a.cols in
  let took () =
    Runtime.pay ctx 1;
    a.a_tip <- false;
    a.a_owned <- false;
    Array { rows = 1; cols = n + 1; store = a.store; a_owned = false; a_tip = true }
  in
  let grown store = Array { rows = 1; cols = n + 1; store; a_owned = true; a_tip = true } in
  let room = max 8 (2 * n) in
  match a.store, x with
  | _ when a.rows <> 1 ->
    Runtime.build ctx (n + 1);
    Arrays.list (Array.init (n + 1) (fun k -> Value.share (if k < n then Value.elt a k else x)))
  | F d, Float y when a.a_tip && n < Float.Array.length d -> Float.Array.set d n y; took ()
  | I d, Int y when a.a_tip && n < Array.length d -> d.(n) <- y; took ()
  | V d, _ when a.a_tip && n < Array.length d -> d.(n) <- Value.share x; took ()
  | F d, Float y ->
    Runtime.build ctx room;
    let out = Float.Array.create room in
    Float.Array.blit d 0 out 0 n;
    Float.Array.set out n y;
    grown (F out)
  | I d, Int y ->
    Runtime.build ctx room;
    let out = Array.make room 0 in
    Array.blit d 0 out 0 n;
    out.(n) <- y;
    grown (I out)
  | V d, _ ->
    Runtime.build ctx room;
    let out = Array.make room Missing in
    for k = 0 to n - 1 do out.(k) <- Value.share d.(k) done;
    out.(n) <- Value.share x;
    grown (V out)
  | _ ->
    Runtime.build ctx (n + 1);
    Arrays.list (Array.init (n + 1) (fun k -> Value.share (if k < n then Value.elt a k else x)))

(* [n] cells of a list, each from the position that [at] gives. *)
let picked a n at = Array.init n (fun k -> Value.share (Value.elt a (at k)))

let list = Arrays.list

let count_arg ctx name v =
  let n = Arrays.whole_index ctx v in
  if n < 0 then Runtime.fail ctx Type (Messages.need_count name (Value.describe v));
  n

let compare_values ctx a b =
  match a, b with
  | (Int _ | Float _), (Int _ | Float _) | Text _, Text _ -> Dict.compare_keys a b
  | _ -> Runtime.fail ctx Type (Messages.cant_sort (Value.describe a) (Value.describe b))

(* A list and the positions of its elements in sorted order. A typed list needs no comparison of values. *)
let sorted_positions ctx name v =
  let a, n = cells ctx name v in
  Runtime.charge ctx (n + 1);
  let compare_at =
    match a.store with
    | F d -> fun i j -> Float.compare (Float.Array.get d i) (Float.Array.get d j)
    | I d -> fun i j -> Int.compare d.(i) d.(j)
    | V d -> fun i j -> compare_values ctx d.(i) d.(j)
  in
  a, Kernels.sort_positions ~parallel:(match a.store with V _ -> false | _ -> true) n compare_at

let sort ctx (a : t array) =
  let x, ks = sorted_positions ctx "Sort" a.(0) in
  if Array.length ks = 0 then list [||] else Arrays.pick ctx x ks 1 (Array.length ks)

let order ctx (a : t array) =
  let _, ks = sorted_positions ctx "Order" a.(0) in
  if Array.length ks = 0 then list [||] else Arrays.of_ints 1 (Array.length ks) (Array.map succ ks)

(* The first m of the positions 0 to n - 1 in the order [cmp], equal ones by position: a heap of the m best so far, the
   last of them at its root, then these m sorted. *)
let first_positions n m cmp =
  let later i j = match cmp i j with 0 -> i > j | c -> c > 0 in
  let heap = Array.make m 0 and size = ref 0 in
  let swap i j = let t = heap.(i) in heap.(i) <- heap.(j); heap.(j) <- t in
  let rec up i = if i > 0 && later heap.(i) heap.((i - 1) / 2) then (swap i ((i - 1) / 2); up ((i - 1) / 2)) in
  let rec down i =
    let l = (2 * i) + 1 in
    let c = if l + 1 < !size && later heap.(l + 1) heap.(l) then l + 1 else l in
    if c < !size && later heap.(c) heap.(i) then (swap c i; down c)
  in
  for p = 0 to n - 1 do
    if !size < m then (heap.(!size) <- p; incr size; up (!size - 1))
    else if m > 0 && later heap.(0) p then (heap.(0) <- p; down 0)
  done;
  Array.stable_sort (fun i j -> if later i j then 1 else if later j i then -1 else 0) heap;
  heap

(* For std/list's Top: the positions of keys, the largest first, equal keys in their order, at least the first n of
   them; [missing] unless [>] orders them as a sort needs (no NaN, no integer past 2^53 among floats), and std/list's
   merge sort then compares them. *)
let descending ctx (a : t array) =
  match a.(0) with
  | Array x ->
    let x = Value.trim x in
    let n = x.rows * x.cols in
    let number = function Int i -> i < 1 lsl 53 && i > -(1 lsl 53) | Float f -> not (Float.is_nan f) | _ -> false in
    let ordered =
      match x.store with
      | I _ -> true
      | F d -> not (Float.Array.exists Float.is_nan d)
      | V d -> Array.for_all (function Text _ -> true | _ -> false) d || Array.for_all number d
    in
    if not ordered then Missing
    else begin
      Runtime.build ctx n;
      Runtime.charge ctx (n + 1);
      let at =
        match x.store with
        | F d -> fun i j -> Float.compare (Float.Array.get d j) (Float.Array.get d i)
        | I d -> fun i j -> Int.compare d.(j) d.(i)
        | V d -> fun i j -> Dict.compare_keys d.(j) d.(i)
      in
      let m = match a.(1) with Int m -> max 0 (min m n) | _ -> n in
      let ks = if m <= n / 8 then first_positions n m at else Kernels.sort_positions ~parallel:true n at in
      if Array.length ks = 0 then list [||] else Arrays.of_ints 1 (Array.length ks) (Array.map succ ks)
    end
  | _ -> Missing

let unique ctx (a : t array) =
  let seen = ref Leaf and others = ref [] and out = ref [] in
  Array.iter
    (fun v ->
       let fresh =
         if Dict.is_key v then begin
           let fresh = Option.is_none (Dict.find ctx v !seen) in
           if fresh then seen := Dict.add ctx v True !seen;
           fresh
         end else begin
           let fresh = not (List.exists (Value.equal ctx v) !others) in
           if fresh then others := v :: !others;
           fresh
         end
       in
       if fresh then out := v :: !out)
    (elements ctx "Unique" a.(0));
  list (Array.of_list (List.rev !out))

let flatten ctx (a : t array) =
  let pieces =
    Array.map
      (fun v ->
         match v with
         | Array _ -> elements ctx "Flatten" v
         | _ -> [| v |])
      (elements ctx "Flatten" a.(0))
  in
  list (Array.concat (Array.to_list pieces))

let zip ctx (a : t array) =
  let xs = elements ctx "Zip" a.(0) and ys = elements ctx "Zip" a.(1) in
  list (Array.init (min (Array.length xs) (Array.length ys)) (fun k -> list [| xs.(k); ys.(k) |]))

let index_of ctx (a : t array) =
  let xs = elements ctx "IndexOf" a.(1) in
  let rec go k =
    if k >= Array.length xs then Missing
    else if Value.equal ctx a.(0) xs.(k) then Int (k + 1)
    else go (k + 1)
  in
  go 0

let points s =
  let out = ref [] and i = ref 0 in
  while !i < String.length s do
    let n = max 1 (Uchar.utf_decode_length (String.get_utf_8_uchar s !i)) in
    out := String.sub s !i n :: !out;
    i := !i + n
  done;
  List.rev !out

let pay ctx s = Runtime.pay_bytes ctx (String.length s)

(* n copies of a text, once the memory they take is granted. *)
let repeated ctx n s =
  let size = String.length s in
  if size > 0 && n > Sys.max_string_length / size then Runtime.limit "memory" ctx.site;
  Runtime.build ctx ((n * size / 8) + 1);
  String.init (n * size) (fun i -> s.[i mod size])

let find ctx (a : t array) =
  let part = text_arg ctx "Find" a.(0) and s = text_arg ctx "Find" a.(1) in
  pay ctx s;
  if part = "" then Int 1
  else
    match Native.find_from s part 0 with
    | -1 -> Missing
    | at -> Int (Native.points_between s 0 at + 1)

let repeat ctx (a : t array) =
  let n = count_arg ctx "Repeat" a.(0) and s = text_arg ctx "Repeat" a.(1) in
  if s = "" then Text "" else Text (repeated ctx n s)

let lines ctx (a : t array) =
  let s = text_arg ctx "Lines" a.(0) in
  let count = ref 0 in
  String.iter (fun c -> if c = '\n' then incr count) s;
  Runtime.build ctx ((String.length s / 8) + (6 * !count) + 1);
  let cut line =
    if String.ends_with ~suffix:"\r" line then String.sub line 0 (String.length line - 1) else line
  in
  let parts = String.split_on_char '\n' s in
  let parts = match List.rev parts with "" :: rest -> List.rev rest | _ -> parts in
  list (Array.of_list (List.map (fun l -> Text (cut l)) parts))

let pad name add ctx (a : t array) =
  let n = count_arg ctx name a.(0) and filler = text_arg ctx name a.(1) and s = text_arg ctx name a.(2) in
  let missing = n - Native.code_points s in
  if missing <= 0 || filler = "" then Text s else Text (add (repeated ctx missing filler) s)

let code ctx (a : t array) =
  let s = text_arg ctx "Code" a.(0) in
  if s = "" then Runtime.fail ctx Type (Messages.need_char "Code") else Int (Uchar.to_int (Uchar.utf_decode_uchar (String.get_utf_8_uchar s 0)))

let byte_position ctx i s =
  if i < 1 || i > String.length s then Runtime.fail ctx Index (Messages.index_outside i (String.length s))

let from_bytes ctx (a : t array) =
  let values = elements ctx "FromBytes" a.(0) in
  let b = Buffer.create (Array.length values) in
  Array.iter
    (fun v ->
       match v with
       | Int i when i >= 0 && i < 256 -> Buffer.add_char b (Char.chr i)
       | _ -> Runtime.fail ctx Type (Messages.need_byte (Value.describe v)))
    values;
  Text (Buffer.contents b)

let bits name f =
  name, nat name 2 2 (fun ctx a -> Int (f (Arrays.whole_index ctx a.(0)) (Arrays.whole_index ctx a.(1))))

let shift x n =
  if n >= Sys.int_size || n <= -Sys.int_size then 0 else if n >= 0 then x lsl n else x lsr -n

let xor_bytes ctx (a : t array) =
  let key = text_arg ctx "xorBytes" a.(0) and s = text_arg ctx "xorBytes" a.(1) in
  if key = "" then Runtime.fail ctx Type (Messages.need_char "xorBytes");
  Runtime.build ctx ((String.length s / 8) + 1);
  Text (String.mapi (fun i c -> Char.chr (Char.code c lxor Char.code key.[i mod String.length key])) s)

let math_natives =
  [ bits "BitAnd" ( land );
    bits "BitOr" ( lor );
    bits "BitXor" ( lxor );
    bits "BitShift" shift;
    "BitNot", nat "BitNot" 1 1 (fun ctx a -> Int (lnot (Arrays.whole_index ctx a.(0)))) ]

let list_natives =
  [ "Append", nat "Append" 2 2 (fun ctx a -> push ctx a.(0) (items ctx "Append" a.(1)));
    "Concat", nat "Concat" 2 2 (fun ctx a ->
        let ys, m = cells ctx "Concat" a.(1) in
        let xs, n = cells ctx "Concat" a.(0) in
        list (Array.init (n + m) (fun k -> Value.share (if k < n then Value.elt xs k else Value.elt ys (k - n)))));
    "Reverse", nat "Reverse" 1 1 (fun ctx a ->
        let xs, n = cells ctx "Reverse" a.(0) in
        list (picked xs n (fun k -> n - 1 - k)));
    "Take", nat "Take" 2 2 (fun ctx a ->
        let xs, n = cells ctx "Take" a.(1) in
        list (picked xs (min (count_arg ctx "Take" a.(0)) n) Fun.id));
    "Skip", nat "Skip" 2 2 (fun ctx a ->
        let xs, n = cells ctx "Skip" a.(1) in
        let k = min (count_arg ctx "Skip" a.(0)) n in
        list (picked xs (n - k) (fun i -> k + i)));
    "IndexOf", nat "IndexOf" 2 2 index_of;
    "Sort", nat "Sort" 1 1 sort;
    "Order", nat "Order" 1 1 order;
    "Unique", nat "Unique" 1 1 unique;
    "Flatten", nat "Flatten" 1 1 flatten;
    "Zip", nat "Zip" 2 2 zip;
    "descending", nat "descending" 2 2 descending ]

let text_natives =
  [ "Upper", nat "Upper" 1 1 (fun ctx a ->
        let s = text_arg ctx "Upper" a.(0) in
        pay ctx s;
        Runtime.reserve ctx ((String.length s / 8) + 1);
        Text (String.uppercase_ascii s));
    "EndsWith", nat "EndsWith" 2 2 (fun ctx a ->
        let suffix = text_arg ctx "EndsWith" a.(0) in
        pay ctx suffix;
        Value.of_bool (String.ends_with ~suffix (text_arg ctx "EndsWith" a.(1))));
    "Find", nat "Find" 2 2 find;
    "Repeat", nat "Repeat" 2 2 repeat;
    "Chars", nat "Chars" 1 1 (fun ctx a ->
        let s = text_arg ctx "Chars" a.(0) in
        Runtime.build ctx (6 * String.length s);
        list (Array.of_list (List.map (fun c -> Text c) (points s))));
    "Code", nat "Code" 1 1 code;
    "Lines", nat "Lines" 1 1 lines;
    "PadLeft", nat "PadLeft" 3 3 (pad "PadLeft" (fun fill s -> fill ^ s));
    "PadRight", nat "PadRight" 3 3 (pad "PadRight" (fun fill s -> s ^ fill));
    "Bytes", nat "Bytes" 1 1 (fun ctx a ->
        let s = text_arg ctx "Bytes" a.(0) in
        Runtime.build ctx (String.length s);
        list (Array.init (String.length s) (fun k -> Int (Char.code s.[k]))));
    "FromBytes", nat "FromBytes" 1 1 from_bytes;
    "Byte", nat "Byte" 2 2 (fun ctx a ->
        let i = Arrays.whole_index ctx a.(0) and s = text_arg ctx "Byte" a.(1) in
        byte_position ctx i s;
        Int (Char.code s.[i - 1]));
    "ByteLength", nat "ByteLength" 1 1 (fun ctx a -> Int (String.length (text_arg ctx "ByteLength" a.(0))));
    "ByteSlice", nat "ByteSlice" 3 3 (fun ctx a ->
        let first = Arrays.whole_index ctx a.(0) and last = Arrays.whole_index ctx a.(1) in
        let s = text_arg ctx "ByteSlice" a.(2) in
        if last < first then Text ""
        else begin
          byte_position ctx first s;
          byte_position ctx last s;
          Runtime.build ctx ((last - first) / 8 + 1);
          Text (String.sub s (first - 1) (last - first + 1))
        end);
    "ByteFind", nat "ByteFind" 3 3 (fun ctx a ->
        let part = text_arg ctx "ByteFind" a.(0) and from = Arrays.whole_index ctx a.(1) in
        let s = text_arg ctx "ByteFind" a.(2) in
        pay ctx part;
        pay ctx s;
        if part = "" then Int from
        else if from < 1 || from > String.length s then Missing
        else
          match Native.find_from s part (from - 1) with
          | -1 -> Missing
          | at -> Int (at + 1)) ]

(* The masking of a WebSocket frame, a small name that only std/websocket sees. *)
let packages =
  [ "math", math_natives; "list", list_natives; "text", text_natives; "websocket", [ "xorBytes", nat "xorBytes" 2 2 xor_bytes ] ]
