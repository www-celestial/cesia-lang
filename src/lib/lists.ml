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
    Array { rows = 1; cols = n + 1; store = a.store; a_owned = false; a_tip = true; dims = [||] }
  in
  let grown store = Array { rows = 1; cols = n + 1; store; a_owned = true; a_tip = true; dims = [||] } in
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

(* The list of the cells at [at 0], [at 1]...: one of floats or of integers stays typed, copied in parallel, where each cell
   was boxed and the whole looked over again. *)
let picked_list ctx (a : arr) n at =
  match a.store with
  | (F _ | I _) when n > 0 -> Arrays.pick ctx a (Array.init n at) 1 n
  | _ -> Arrays.list (picked a n at)

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
    let n = snd (Native.char_at s !i) in
    out := String.sub s !i n :: !out;
    i := !i + n
  done;
  List.rev !out

let pay ctx s = Runtime.pay_bytes ctx (String.length s)

(* Number [k] of Casefold.runs, and how many it holds. *)
let[@inline] fold_at k = Int32.to_int (String.get_int32_le Casefold.runs (4 * k))
let fold_count = String.length Casefold.runs / 4

(* The run of Casefold.runs whose first character is the last at or below p, found by halves: its index there. *)
let run_of p =
  let rec find lo hi =
    if hi - lo <= 1 then lo
    else
      let mid = (lo + hi) / 2 in
      if fold_at (4 * mid) <= p then find mid hi else find lo mid
  in
  4 * find 0 (fold_count / 4)

(* A character may fold to one a byte longer (U+023A, two bytes, to U+2C65, three): the folded text is at most half
   again as long. *)
let folded_size n = n + (n / 2)

(* Each character of a text to its simple case folding, A to Z without a search. Bytes that aren't UTF-8 stay as they
   are. A text of ASCII without a capital is given back as it is, without a copy. A text mostly keeps to one script: the
   run found for a character, from its first character to the next run's, serves the next one without a search. *)
let fold s =
  let n = String.length s in
  let rec start i =
    if i < n && (match s.[i] with 'A' .. 'Z' | '\128' .. '\255' -> false | _ -> true) then start (i + 1) else i
  in
  let i = start 0 in
  if i = n then s
  else begin
    let out = Bytes.create (folded_size n) in
    Bytes.blit_string s 0 out 0 i;
    let rec go i j k next =
      if i >= n then j
      else if s.[i] < '\128' then begin
        Bytes.set out j (Char.lowercase_ascii s.[i]);
        go (i + 1) (j + 1) k next
      end else begin
        let d = String.get_utf_8_uchar s i in
        let w = Uchar.utf_decode_length d and p = Uchar.to_int (Uchar.utf_decode_uchar d) in
        let k, next =
          if p >= fold_at k && p < next then k, next
          else
            let k = run_of p in
            k, if k + 4 < fold_count then fold_at (k + 4) else max_int
        in
        let moves = p >= fold_at k && p <= fold_at (k + 1) && (p - fold_at k) land (fold_at (k + 2) - 1) = 0 in
        if moves && Uchar.utf_decode_is_valid d then
          go (i + w) (j + Bytes.set_utf_8_uchar out j (Uchar.of_int (p + fold_at (k + 3)))) k next
        else begin
          Bytes.blit_string s i out j w;
          go (i + w) (j + w) k next
        end
      end
    in
    Bytes.sub_string out 0 (go i i 0 0)
  end

(* n copies of a text, once the memory they take is granted. *)
let repeated ctx n s =
  let size = String.length s in
  if size > 0 && n > Sys.max_string_length / size then Runtime.limit "memory" ctx.site;
  Runtime.build ctx ((n * size / 8) + 1);
  let total = n * size in
  if size = 1 then String.make n s.[0]
  else if total = 0 then ""
  else begin
    (* The copies made so far, copied after themselves: log n copies of memory, not a call per byte. *)
    let b = Bytes.create total in
    Bytes.blit_string s 0 b 0 size;
    let filled = ref size in
    while !filled < total do
      let k = min !filled (total - !filled) in
      Bytes.blit b 0 b !filled k;
      filled := !filled + k
    done;
    Bytes.to_string b
  end

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
  if s = "" then Runtime.fail ctx Type (Messages.need_char "Code") else Int (fst (Native.char_at s 0))

let byte_position ctx i s =
  if i < 1 || i > String.length s then Runtime.fail ctx Index (Messages.text_outside i (String.length s) "bytes")

(* The tables of text.ByteFindAny, one int for each byte: 1 at the bytes of the set, or with [out] at the others. Making
   one costs more than a short search, and a lexer looks for the same few sets again and again: the last eight made are
   kept, each slot a triple that never changes, so a domain reads it whole; a slot never used has the flag 2, which no
   call has. A set of more than 256 bytes repeats some, and isn't kept: no large text is held. *)
let byte_tables = Array.init 8 (fun _ -> Atomic.make ("", 2, [||]))
let next_table = Atomic.make 0

let rec byte_table set out k =
  if k = Array.length byte_tables then begin
    let t = Array.make 256 out in
    for i = 0 to String.length set - 1 do t.(Char.code set.[i]) <- 1 - out done;
    let slot = Atomic.fetch_and_add next_table 1 land 7 in
    if String.length set <= 256 then Atomic.set byte_tables.(slot) (set, out, t);
    t
  end
  else
    let s, o, t = Atomic.get byte_tables.(k) in
    if o = out && (s == set || String.equal s set) then t else byte_table set out (k + 1)

(* The first of the four bytes of [x] from the [k]th that is 1 in [t], when there is one. *)
let rec within (t : int array) x k = if t.((x lsr (8 * k)) land 255) <> 0 then k else within t x (k + 1)

(* The first place of [s] from [i] on whose byte is 1 in [t], or the length of [s]: eight bytes at a time, read as one
   word, while none of them is, then the first of the four that hold one; the last seven, byte by byte. *)
let first_in (t : int array) s i =
  let n = String.length s and i = ref i and found = ref (-1) in
  while !found < 0 && !i + 8 <= n do
    let w = String.get_int64_le s !i in
    let x = Int64.to_int w and y = Int64.to_int (Int64.shift_right_logical w 32) in
    if t.(x land 255) lor t.((x lsr 8) land 255) lor t.((x lsr 16) land 255) lor t.((x lsr 24) land 255) <> 0 then
      found := !i + within t x 0
    else if t.(y land 255) lor t.((y lsr 8) land 255) lor t.((y lsr 16) land 255) lor t.((y lsr 24) land 255) <> 0 then
      found := !i + 4 + within t y 0
    else i := !i + 8
  done;
  if !found >= 0 then !found
  else begin
    while !i < n && t.(Char.code s.[!i]) = 0 do incr i done;
    !i
  end

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

(* The numbers that the bytes of a text hold one after another, little-endian as x86 and ARM keep them, of a kind named
   as std/c names it: what a binary file, as an STL mesh, holds. Floats and integers come out without a box. *)
let number_size = function "u8" | "i8" -> 1 | "u16" | "i16" -> 2 | "u32" | "i32" | "f32" -> 4 | "f64" -> 8 | _ -> 0

let kind_arg ctx name v =
  let kind = text_arg ctx name v in
  let size = number_size kind in
  if size = 0 then Runtime.fail ctx Type (Messages.number_kind name kind);
  kind, size

let numbers ctx (a : t array) =
  let (kind, size), s = kind_arg ctx "Numbers" a.(0), text_arg ctx "Numbers" a.(1) in
  let n = String.length s / size in
  if n * size <> String.length s then Runtime.fail ctx Type (Messages.number_bytes kind size (String.length s));
  Runtime.pay ctx n;
  if kind.[0] = 'f' then begin
    let d = Runtime.alloc_float ctx n 0.0 in
    for k = 0 to n - 1 do
      Float.Array.set d k
        (if size = 4 then Int32.float_of_bits (String.get_int32_le s (4 * k)) else Int64.float_of_bits (String.get_int64_le s (8 * k)))
    done;
    Arrays.of_float 1 n d
  end
  else begin
    let get =
      match kind with
      | "u8" -> String.get_uint8 s
      | "i8" -> String.get_int8 s
      | "u16" -> fun k -> String.get_uint16_le s (2 * k)
      | "i16" -> fun k -> String.get_int16_le s (2 * k)
      | "u32" -> fun k -> Int32.to_int (String.get_int32_le s (4 * k)) land 0xFFFF_FFFF
      | _ -> fun k -> Int32.to_int (String.get_int32_le s (4 * k))
    in
    let d = Runtime.alloc_ints ctx n 0 in
    for k = 0 to n - 1 do d.(k) <- get k done;
    Arrays.of_ints 1 n d
  end

let from_numbers ctx (a : t array) =
  let kind, size = kind_arg ctx "FromNumbers" a.(0) in
  let xs, n = cells ctx "FromNumbers" a.(1) in
  Runtime.reserve ctx ((n * size / 8) + 1);
  let b = Bytes.create (n * size) in
  let lo, hi =
    match kind with
    | "u8" -> 0, 255 | "i8" -> -128, 127 | "u16" -> 0, 65535 | "i16" -> -32768, 32767 | "u32" -> 0, 0xFFFF_FFFF
    | _ -> -0x8000_0000, 0x7FFF_FFFF
  in
  let wrong k = Runtime.fail ctx Type (Messages.number_of kind (k + 1) (Value.describe (Value.elt xs k))) in
  for k = 0 to n - 1 do
    if kind.[0] = 'f' then begin
      let x = match xs.store with F d -> Float.Array.get d k | I d -> float_of_int d.(k) | V d -> (match d.(k) with Float x -> x | Int i -> float_of_int i | _ -> wrong k) in
      if size = 4 then Bytes.set_int32_le b (4 * k) (Int32.bits_of_float x) else Bytes.set_int64_le b (8 * k) (Int64.bits_of_float x)
    end
    else begin
      let i =
        match xs.store with
        | I d -> d.(k)
        | F d -> let x = Float.Array.get d k in if Float.is_integer x && Float.abs x < 1e10 then int_of_float x else wrong k
        | V _ -> (match Value.elt xs k with Int i -> i | Float x when Float.is_integer x && Float.abs x < 1e10 -> int_of_float x | _ -> wrong k)
      in
      if i < lo || i > hi then wrong k;
      if size = 1 then Bytes.set_uint8 b k (i land 255)
      else if size = 2 then Bytes.set_uint16_le b (2 * k) (i land 0xFFFF)
      else Bytes.set_int32_le b (4 * k) (Int32.of_int i)
    end
  done;
  Text (Bytes.to_string b)

let bits name f =
  name, nat name 2 2 (fun ctx a -> Int (f (Arrays.whole_index ctx a.(0)) (Arrays.whole_index ctx a.(1))))

(* Right, the sign kept, as Python and Go shift: -8 by -1 is -4. Left, on 63 bits: the bits past them are lost. *)
let shift x n =
  if n >= Sys.int_size then 0 else if n >= 0 then x lsl n else x asr (if n < 1 - Sys.int_size then Sys.int_size - 1 else - n)

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
        picked_list ctx xs n (fun k -> n - 1 - k));
    "Take", nat "Take" 2 2 (fun ctx a ->
        let xs, n = cells ctx "Take" a.(1) in
        picked_list ctx xs (min (count_arg ctx "Take" a.(0)) n) Fun.id);
    "Skip", nat "Skip" 2 2 (fun ctx a ->
        let xs, n = cells ctx "Skip" a.(1) in
        let k = min (count_arg ctx "Skip" a.(0)) n in
        picked_list ctx xs (n - k) (fun i -> k + i));
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
    "Fold", nat "Fold" 1 1 (fun ctx a ->
        let s = text_arg ctx "Fold" a.(0) in
        pay ctx s;
        Runtime.reserve ctx ((folded_size (String.length s) / 8) + 1);
        Text (fold s));
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
    "Numbers", nat "Numbers" 2 2 numbers;
    "FromNumbers", nat "FromNumbers" 2 2 from_numbers;
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
    (* It pays for the bytes it read, not for the whole text: the next line end of a large text costs a line. *)
    "ByteFind", nat ~params:[| "part"; "from"; "s"; "fold" |] "ByteFind" 3 4 (fun ctx a ->
        let part = text_arg ctx "ByteFind" a.(0) and from = Arrays.whole_index ctx a.(1) in
        let s = text_arg ctx "ByteFind" a.(2) in
        let fold = Native.flag_arg ctx "fold" a 3 in
        if part = "" then Int from
        else if from < 1 || from > String.length s then Missing
        else begin
          let at = Native.find_from ~fold s part (from - 1) in
          Runtime.pay_bytes ctx ((if at < 0 then String.length s else at + String.length part) - from + 1);
          if at < 0 then Missing else Int (at + 1)
        end);
    (* It pays for the bytes of the set and for those it read, as ByteFind: skipping a word costs the word. *)
    "ByteFindAny", nat ~params:[| "bytes"; "from"; "s"; "not" |] "ByteFindAny" 3 4 (fun ctx a ->
        let set = text_arg ctx "ByteFindAny" a.(0) and from = Arrays.whole_index ctx a.(1) in
        let s = text_arg ctx "ByteFindAny" a.(2) in
        let out = Bool.to_int (Native.flag_arg ctx "not" a 3) and n = String.length s in
        if from < 1 || from > n then Missing
        else begin
          let at = first_in (byte_table set out 0) s (from - 1) in
          let found = at < n in
          Runtime.pay_bytes ctx (String.length set + (if found then at + 1 else n) - from + 1);
          if found then Int (at + 1) else Missing
        end) ]

(* The value of each byte as a digit of Base64, standard or for URLs (RFC 4648 §4 and §5), 255 for the others; made at the
   first use. *)
let base64_digits =
  lazy
    (String.init 256 (fun i ->
         match Char.chr i with
         | 'A' .. 'Z' -> Char.chr (i - 65)
         | 'a' .. 'z' -> Char.chr (i - 71)
         | '0' .. '9' -> Char.chr (i + 4)
         | '+' | '-' -> '\062'
         | '/' | '_' -> '\063'
         | _ -> '\255'))

(* The bytes of Base64 with or without padding, or missing for a text that isn't Base64. The padding is one or two = at
   the end of a text of a multiple of four: one elsewhere, as two texts of Base64 put end to end, decoded to wrong bytes.
   The bits past the last whole byte are dropped, as encode.Unbase64 always did. Four digits make three bytes, with no
   test inside the loop: a screenshot of a page is a megabyte of Base64. *)
let unbase64 ctx (a : t array) =
  let s = text_arg ctx "unbase64" a.(0) in
  Runtime.pay_bytes ctx (String.length s);
  let whole = String.length s in
  let pad = if whole > 0 && s.[whole - 1] = '=' then if whole > 1 && s.[whole - 2] = '=' then 2 else 1 else 0 in
  let n = whole - pad and d = Lazy.force base64_digits in
  if (pad > 0 && whole mod 4 <> 0) || (match String.index_opt s '=' with Some i -> i < n | None -> false) then Missing
  else begin
  Runtime.build ctx ((n / 10) + 1);
  let out = Bytes.create (n * 3 / 4) and bad = ref 0 and i = ref 0 and o = ref 0 in
  let digit k = if k < n then Char.code d.[Char.code s.[k]] else 0 in
  while !i + 4 <= n do
    let a = Char.code d.[Char.code s.[!i]] and b = Char.code d.[Char.code s.[!i + 1]] in
    let c = Char.code d.[Char.code s.[!i + 2]] and e = Char.code d.[Char.code s.[!i + 3]] in
    bad := !bad lor a lor b lor c lor e;
    let w = (a lsl 18) lor (b lsl 12) lor (c lsl 6) lor e in
    Bytes.set_uint16_be out !o (w lsr 8);
    Bytes.set_uint8 out (!o + 2) (w land 255);
    i := !i + 4;
    o := !o + 3
  done;
  let w = (digit !i lsl 18) lor (digit (!i + 1) lsl 12) lor (digit (!i + 2) lsl 6) in
  bad := !bad lor digit !i lor digit (!i + 1) lor digit (!i + 2);
  for k = 0 to Bytes.length out - !o - 1 do Bytes.set_uint8 out (!o + k) ((w lsr (16 - (8 * k))) land 255) done;
  if n mod 4 = 1 || !bad >= 64 then Missing else Text (Bytes.to_string out)
  end

let packages =
  [ "math", math_natives; "list", list_natives; "text", text_natives; "encode", [ "unbase64", nat "unbase64" 1 1 unbase64 ] ]
