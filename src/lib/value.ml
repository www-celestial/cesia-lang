open Types

exception Kerr of { kind : kind; text : string; hint : string option; at : int }
exception Limit of { what : string; at : int }
exception Quit of int

let of_bool b = if b then True else False

(* The keys and values of a map, k1 v1 k2 v2..., in the order of insertion; a struct's fields by name. *)
let items v =
  match v with
  | Struct r -> Array.init (2 * Trie.nvals r.fields) (fun j -> if j land 1 = 0 then Text r.shape.names.(j / 2) else Trie.vget r.fields (j / 2))
  | _ -> Trie.items v

let share = Trie.share

let kind_name = function
  | Syntax -> "syntax"
  | Name -> "name"
  | Type -> "type"
  | Index -> "index"
  | Field -> "field"
  | Math -> "math"
  | Permission -> "permission"
  | User -> "user"

(* The first of 15, 16 and 17 significant digits that reads back identically, in a single spelling: 1.0, 1e20, 1.5e-7.
   Its own bytes, so that any domain can call it; [write] and json.ml use [scratch], on the main domain. *)
let float_text x =
  let b = Bytes.create 24 in
  Bytes.sub_string b 0 (Ryu.write b 0 x)

let[@inline] elt a k =
  match a.store with
  | F d -> Float (Float.Array.get d k)
  | I d -> Int d.(k)
  | V d -> d.(k)

(* The same sizes: a matrix of 2 by 12 isn't an array of 2 by 3 by 4. *)
let same_shape x y = x.rows = y.rows && x.cols = y.cols && (x.dims == y.dims || x.dims = y.dims)

(* The free cells behind a list stay behind: this is for code that reads a store as a whole. *)
let trim a =
  let n = a.rows * a.cols in
  (match a.store with
   | F d -> if Float.Array.length d <> n then a.store <- F (Float.Array.sub d 0 n)
   | I d -> if Array.length d <> n then a.store <- I (Array.sub d 0 n)
   | V d -> if Array.length d <> n then a.store <- V (Array.sub d 0 n));
  a

let is_number = function Int _ | Float _ -> true | _ -> false

(* A struct belongs to its package: two packages can each have a Rect, with its own methods. Ok and Err have one shape for
   everyone, since natives build them and ? compares them. *)
let struct_module sname m = match sname with "Ok" | "Err" -> -1 | _ -> m

let shape_of w ?sname ?(m = -1) names =
  let sm = match sname with Some n -> struct_module n m | None -> m in
  let key =
    match sname with
    | Some n when sm >= 0 -> Array.append [| Printf.sprintf "#%d:%s" sm n |] names
    | Some n -> Array.append [| "#" ^ n |] names
    | None -> names
  in
  match Hashtbl.find_opt w.shapes key with
  | Some s -> s
  | None ->
    let s = { sid = Hashtbl.length w.shapes; names; sname; sm; next = Hashtbl.create 4; checks = [||] } in
    Hashtbl.add w.shapes key s;
    s

let field_index shape name =
  let n = Array.length shape.names in
  let rec go i = if i >= n then -1 else if String.equal shape.names.(i) name then i else go (i + 1) in
  go 0

let result w sname field v =
  Struct { shape = shape_of w ~sname [| field |]; fields = V [| share v |]; r_owned = true }

(* The natives give an Ok or an Err at each call: their shapes are looked up once, for the last world that asked. *)
let ok_shape = ref None
let err_shape = ref None

let cached cache w sname field =
  match !cache with
  | Some (w', s) when w' == w -> s
  | _ ->
    let s = shape_of w ~sname [| field |] in
    cache := Some (w, s);
    s

let ok w v = Struct { shape = cached ok_shape w "Ok" "Value"; fields = V [| share v |]; r_owned = true }
let err w v = Struct { shape = cached err_shape w "Err" "Error"; fields = V [| share v |]; r_owned = true }

let failure_keys = Trie.names [| "Kind"; "Message" |]
let failure w kind text = err w (Trie.record failure_keys [| Text kind; Text text |])

let nested ctx depth =
  if depth > ctx.w.limits.nesting then raise (Limit { what = "nesting"; at = -1 })

(* Showing and comparing are natives: they count their steps, otherwise a highly shared value, which fits in little
   memory, would escape --limit steps. *)
let pay ctx n = ctx.w.charge ctx ((n / 16) + 1)

(* An integer in decimal, as string_of_int writes it, without C's printf: two digits by a division by 100, which the
   compiler makes a multiplication, read from a table of the pairs. The work is on the negative side, where min_int fits.
   The digits go to [scratch], then out in one copy, the one allocation; texts are made on the main domain only. *)
let small_ints = Array.init 10 string_of_int
let pairs = String.init 200 (fun j -> Char.chr (48 + if j land 1 = 0 then j / 20 else j / 2 mod 10))
let scratch = Bytes.create 64

(* The digits of [i] written in [scratch] from [at]: where they end. *)
let digits at i =
  let x = if i < 0 then i else -i and sign = if i < 0 then 1 else 0 in
  let n = ref (sign + 1) and p = ref (x / 10) in
  while !p <> 0 do incr n; p := !p / 10 done;
  let b = scratch and x = ref x and j = ref (at + !n - 1) in
  while !x <= -100 do
    let q = !x / 100 in
    let r = (q * 100) - !x in
    Bytes.set b !j pairs.[(2 * r) + 1];
    Bytes.set b (!j - 1) pairs.[2 * r];
    x := q;
    j := !j - 2
  done;
  if !x <= -10 then begin
    Bytes.set b !j pairs.[(-2 * !x) + 1];
    Bytes.set b (!j - 1) pairs.[-2 * !x]
  end
  else Bytes.set b !j (Char.chr (48 - !x));
  if sign = 1 then Bytes.set b at '-';
  at + !n

let int_text i = if i >= 0 && i < 10 then small_ints.(i) else Bytes.sub_string scratch 0 (digits 0 i)

(* A text being written by [write]. [left] is the number of characters (code points, counted as value.Len counts them)
   that still fit: past them, [Full] stops the walk, the buffer holding exactly the characters that fit. With [left] =
   max_int nothing is counted, and the text is whole. [cap] bounds the bytes of a text that isn't UTF-8, whose
   continuation bytes alone count no character: 4 bytes a character, which UTF-8 never reaches before [left] does. *)
type out = { b : Buffer.t; mutable left : int; cap : int }

exception Full

(* [len] bytes of [s] from [pos], as many of their characters as fit. *)
let add_sub o s pos len =
  if o.left = max_int then Buffer.add_substring o.b s pos len
  else begin
    let stop = pos + max 0 (min len (o.cap - Buffer.length o.b)) in
    for i = pos to stop - 1 do
      if Char.code s.[i] land 0xC0 <> 0x80 then begin
        if o.left = 0 then begin
          Buffer.add_substring o.b s pos (i - pos);
          raise Full
        end;
        o.left <- o.left - 1
      end
    done;
    Buffer.add_substring o.b s pos (stop - pos);
    if stop < pos + len then raise Full
  end

let add o s = add_sub o s 0 (String.length s)

(* The first [n] bytes of [b], all ASCII. *)
let add_ascii o b n =
  if o.left >= n then begin
    if o.left <> max_int then o.left <- o.left - n;
    Buffer.add_subbytes o.b b 0 n
  end
  else begin
    Buffer.add_subbytes o.b b 0 o.left;
    raise Full
  end

let add_char o c =
  if o.left = max_int then Buffer.add_char o.b c
  else if o.left = 0 then raise Full
  else begin
    o.left <- o.left - 1;
    Buffer.add_char o.b c
  end

(* A separator: the mark, then a space. *)
let add_sep o c =
  add_char o c;
  add_char o ' '

(* A text in quotes, its quotes and backslashes escaped. A run between them goes out as soon as it has more bytes than
   characters fit, each byte being at most one character: a long text stops being read soon after the text is full. *)
let add_quoted o s =
  add_char o '"';
  let n = String.length s in
  let rec go from i =
    if i = n then add_sub o s from (i - from)
    else
      match s.[i] with
      | ('"' | '\\') as c ->
        add_sub o s from (i - from);
        add_char o '\\';
        add_char o c;
        go (i + 1) (i + 1)
      | _ when i - from > o.left ->
        add_sub o s from (i - from);
        go i (i + 1)
      | _ -> go from (i + 1)
  in
  go 0 0;
  add_char o '"'

let quote s =
  let o = { b = Buffer.create (String.length s + 2); left = max_int; cap = max_int } in
  add_quoted o s;
  Buffer.contents o.b

(* How many of [n] values a walk may write: each writes at least one character, so no more than one past those that fit. *)
let visits o n = if o.left < n then o.left + 1 else n

(* Only numbers: a matrix of them separates its columns with spaces. *)
let numeric a n =
  match a.store with
  | F _ | I _ -> true
  | V d ->
    let rec go k = k = n || (is_number d.(k) && go (k + 1)) in
    go 0

(* The text of a value that holds no other and isn't a text, which needs no buffer; "" for the others, which [write] walks. *)
let word = function
  | Missing -> "missing"
  | Undef | Bound _ -> "undefined"
  | True -> "true"
  | False -> "false"
  | Int i -> int_text i
  | Float x -> float_text x
  | Fun c -> "function " ^ c.proto.pname
  | Native n -> "function " ^ n.nname
  | Handle h -> Printf.sprintf "<%s %d>" h.kind h.id
  | Text _ | Array _ | Dict _ | Struct _ -> ""

(* The value written as code, in [o]. *)
let rec write o ctx depth v =
  nested ctx depth;
  match v with
  | Int i -> if i >= 0 && i < 10 then add_char o (Char.chr (48 + i)) else add_ascii o scratch (digits 0 i)
  | Float x -> add_ascii o scratch (Ryu.write scratch 0 x)
  | Text s -> add_quoted o s
  | Array a -> write_array o ctx depth a
  | Dict _ -> write_map o ctx depth (items v)
  | Struct r -> write_struct o ctx depth r.shape r.fields
  | v -> add o (word v)

(* A key that is a name as the code writes it, {Name: 1}, another as a value, {"a-b": 1, 2: 3}. *)
and write_map o ctx depth kv =
  let n = Array.length kv / 2 in
  pay ctx (visits o n);
  add_char o '{';
  for i = 0 to n - 1 do
    if i > 0 then add_sep o ',';
    (match kv.(2 * i) with Text s when Lexer.is_plain_name s -> add o s | k -> write o ctx (depth + 1) k);
    add_sep o ':';
    write o ctx (depth + 1) kv.((2 * i) + 1)
  done;
  add_char o '}'

(* A struct with one field shows its value only, as the code builds it: Ok(42). More fields show their names. *)
and write_struct o ctx depth (shape : shape) fields =
  let names = shape.names in
  let n = Array.length names in
  pay ctx (visits o n);
  (match shape.sname with Some sname -> add o sname | None -> ());
  add_char o '(';
  if n = 1 && shape.sname <> None then write o ctx (depth + 1) (Trie.vget fields 0)
  else
    for i = 0 to n - 1 do
      if i > 0 then add_sep o ',';
      add o names.(i);
      add o " = ";
      write o ctx (depth + 1) (Trie.vget fields i)
    done;
  add_char o ')'

and write_array o ctx depth a =
  let n = a.rows * a.cols in
  pay ctx (visits o n);
  if n = 0 then add o "[]"
  else if Array.length a.dims > 0 then write_slices o ctx depth a (numeric a n)
  else begin
    add_char o '[';
    if a.rows = 1 || a.cols = 1 then begin
      let mark = if a.rows = 1 then ',' else ';' in
      for k = 0 to n - 1 do
        if k > 0 then add_sep o mark;
        write o ctx (depth + 1) (elt a k)
      done
    end
    else write_rows o ctx depth a 0 a.rows a.cols (numeric a n);
    add_char o ']'
  end

(* The rows of the [r] by [c] matrix that starts at [first] in [a]'s store, its columns apart by a space when [num], else
   by a comma. *)
and write_rows o ctx depth a first r c num =
  for i = 0 to r - 1 do
    if i > 0 then add_sep o ';';
    for j = 0 to c - 1 do
      if j > 0 then (if num then add_char o ' ' else add_sep o ',');
      write o ctx (depth + 1) (elt a (first + (j * r) + i))
    done
  done

(* Three dimensions or more: each matrix of the first two, as a matrix shows, then ;;; before the next along the third,
   ;;;; along the fourth, and so on, as Julia writes them: [1 3; 2 4;;; 5 7; 6 8] is 2 by 2 by 2. *)
and write_slices o ctx depth a num =
  let r = a.dims.(0) and c = a.dims.(1) in
  let slices = (a.rows * a.cols) / (r * c) in
  add_char o '[';
  for s = 0 to slices - 1 do
    if s > 0 then begin
      (* One more ; for each dimension past the second that starts again here. *)
      let rec semis d step = if d < Array.length a.dims - 1 && s mod (step * a.dims.(d)) = 0 then semis (d + 1) (step * a.dims.(d)) else d in
      add o (String.make (semis 2 1 + 1) ';');
      add_char o ' '
    end;
    write_rows o ctx depth a (s * r * c) r c num
  done;
  add_char o ']'

let show ctx v =
  match v with
  | Text _ | Array _ | Dict _ | Struct _ ->
    let o = { b = Buffer.create 64; left = max_int; cap = max_int } in
    write o ctx 0 v;
    Buffer.contents o.b
  | v -> word v

let text_of ctx v = match v with Text s -> s | _ -> show ctx v

(* The text of [text_of], cut: whole when it has at most [most] characters, else its first [most - 1] and an ellipsis. *)
let text_upto ctx most v =
  match v with
  | Text s when String.length s <= most -> s
  | _ -> (
    let o = { b = Buffer.create 64; left = most; cap = (if most > max_int / 4 then max_int else 4 * most) } in
    match (match v with Text s -> add o s | _ -> write o ctx 0 v) with
    | () -> Buffer.contents o.b
    | exception Full ->
      (* The buffer holds [most] characters, fewer for a text that isn't UTF-8: the last one gives its place to the
         ellipsis. *)
      let s = Buffer.contents o.b in
      let rec start i = if i > 0 && Char.code s.[i] land 0xC0 = 0x80 then start (i - 1) else i in
      String.sub s 0 (start (String.length s - 1)) ^ "\u{2026}")

(* Out of line: inlined in [describe], it slows down the hot code that names a value on its cold path. *)
let[@inline never] struct_name n = Messages.article n

(* How a message names a value. *)
let describe v =
  match v with
  | Int i -> "the number " ^ string_of_int i
  | Float x -> "the number " ^ float_text x
  | Text s -> "the text " ^ quote s
  | Missing -> "missing"
  | True -> "true"
  | False -> "false"
  | Array _ -> "an array"
  | Struct { shape = { sname = Some n; _ }; _ } -> struct_name n
  | Struct _ -> "a struct"
  | Fun c -> "function " ^ c.proto.pname
  | Native n -> "function " ^ n.nname
  | Handle h -> "a " ^ h.kind
  | Dict _ -> "a dictionary"
  | Undef | Bound _ -> "an undefined value"

let type_of v =
  match v with
  | Int _ -> "an Int"
  | Float _ -> "a Float"
  | Text _ -> "a Text"
  | True | False -> "a Bool"
  | Array _ -> "an Array"
  | Dict _ -> "a Dict"
  | Fun _ | Native _ -> "a Function"
  | _ -> describe v

let rec equal ctx a b = equal_at ctx 0 a b

and equal_at ctx depth a b =
  nested ctx depth;
  match a, b with
  | Array x, Array y ->
    (x.rows * x.cols = 0 && y.rows * y.cols = 0)
    || same_shape x y
    && begin
      let n = x.rows * x.cols in
      pay ctx n;
      let rec go k = k >= n || (equal_at ctx (depth + 1) (elt x k) (elt y k) && go (k + 1)) in
      go 0
    end
  | Struct x, Struct y ->
    let n = Trie.nvals x.fields in
    x.shape.sname = y.shape.sname && n = Trie.nvals y.fields
    && begin
      pay ctx n;
      let rec go i =
        i >= n
        || begin
          let k = if x.shape == y.shape then i else field_index y.shape x.shape.names.(i) in
          k >= 0 && equal_at ctx (depth + 1) (Trie.vget x.fields i) (Trie.vget y.fields k) && go (i + 1)
        end
      in
      go 0
    end
  | Int x, Int y -> x = y
  | Float x, Float y -> x = y || (Float.is_nan x && Float.is_nan y)
  | Int x, Float y | Float y, Int x -> float_of_int x = y
  | True, True | False, False | Missing, Missing -> true
  | Text x, Text y -> String.equal x y
  | Fun x, Fun y -> x.proto == y.proto && x.env == y.env
  | Native x, Native y -> x == y
  | Handle x, Handle y -> x.id = y.id && String.equal x.kind y.kind
  | Dict { keys = { deep = Flat; _ } as kx; vals = vx; _ }, Dict { keys = { deep = Flat; _ } as ky; vals = vy; _ } when kx == ky && Trie.nvals vx = Trie.nvals vy ->
    let n = Trie.nvals vx in
    pay ctx n;
    let rec go i = i >= n || (equal_at ctx (depth + 1) (Trie.vget vx i) (Trie.vget vy i) && go (i + 1)) in
    go 0
  | Dict _, Dict _ ->
    let n = Trie.length a in
    n = Trie.length b
    && begin
      pay ctx n;
      let o = Trie.items a in
      let rec go i =
        i >= n
        || begin
          let k = o.(2 * i) in
          let y = Trie.find b (Trie.hash k) k in
          y != Undef && equal_at ctx (depth + 1) o.((2 * i) + 1) y && go (i + 1)
        end
      in
      go 0
    end
  | _ -> false
