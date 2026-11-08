open Types

exception Kerr of { kind : kind; text : string; hint : string option; at : int }
exception Limit of { what : string; at : int }
exception Quit of int

let of_bool b = if b then True else False

(* The keys and values of a map, k1 v1 k2 v2..., in the order of insertion; a struct's fields by name. *)
let items v =
  match v with
  | Struct r -> Array.init (2 * Array.length r.fields) (fun j -> if j land 1 = 0 then Text r.shape.names.(j / 2) else r.fields.(j / 2))
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

(* The first format that reads back identically, in a single spelling: 1.0, 1e20, 1.5e-7. *)
let float_text x =
  if Float.is_nan x then "nan"
  else if x = infinity then "inf"
  else if x = neg_infinity then "-inf"
  else begin
    let s = Printf.sprintf "%.15g" x in
    let s = if float_of_string s = x then s else Printf.sprintf "%.16g" x in
    let s = if float_of_string s = x then s else Printf.sprintf "%.17g" x in
    match String.index_opt s 'e' with
    | Some i ->
      let mant = String.sub s 0 i in
      let exp = int_of_string (let r = String.sub s (i + 1) (String.length s - i - 1) in
                               if r.[0] = '+' then String.sub r 1 (String.length r - 1) else r) in
      Printf.sprintf "%se%d" mant exp
    | None -> if String.contains s '.' then s else s ^ ".0"
  end

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (function '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\" | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

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
  Struct { shape = shape_of w ~sname [| field |]; fields = [| share v |]; r_owned = true }

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

let ok w v = Struct { shape = cached ok_shape w "Ok" "Value"; fields = [| share v |]; r_owned = true }
let err w v = Struct { shape = cached err_shape w "Err" "Error"; fields = [| share v |]; r_owned = true }

let failure_keys = Trie.names [| "Kind"; "Message" |]
let failure w kind text = err w (Trie.record failure_keys [| Text kind; Text text |])

let nested ctx depth =
  if depth > ctx.w.limits.nesting then raise (Limit { what = "nesting"; at = -1 })

(* Showing and comparing are natives: they count their steps, otherwise a highly shared value, which fits in little
   memory, would escape --limit steps. *)
let pay ctx n = ctx.w.charge ctx ((n / 16) + 1)

(* An integer in decimal, as string_of_int writes it, without C's printf: two digits by a division by 100, which the
   compiler makes a multiplication, read from a table of the pairs. The work is on the negative side, where min_int fits. *)
let small_ints = Array.init 10 string_of_int
let pairs = String.init 200 (fun j -> Char.chr (48 + if j land 1 = 0 then j / 20 else j / 2 mod 10))

let int_text i =
  if i >= 0 && i < 10 then small_ints.(i)
  else begin
    let x = if i < 0 then i else -i and sign = if i < 0 then 1 else 0 in
    let n = ref sign and p = ref x in
    while !p <> 0 do incr n; p := !p / 10 done;
    let b = Bytes.create !n and x = ref x and j = ref (!n - 1) in
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
    if sign = 1 then Bytes.set b 0 '-';
    Bytes.to_string b
  end

let rec show ctx v = show_at ctx 0 v

and show_at ctx depth v =
  nested ctx depth;
  match v with
  | Missing -> "missing"
  | Undef | Bound _ -> "undefined"
  | True -> "true"
  | False -> "false"
  | Int i -> int_text i
  | Float x -> float_text x
  | Text s -> quote s
  | Array a -> show_array ctx depth a
  | Dict _ -> show_map ctx depth (items v)
  | Struct r -> show_struct ctx depth r.shape r.fields
  | Fun c -> "function " ^ c.proto.pname
  | Native n -> "function " ^ n.nname
  | Handle h -> Printf.sprintf "<%s %d>" h.kind h.id

(* A key that is a name as the code writes it, {Name: 1}, another as a value, {"a-b": 1, 2: 3}. *)
and show_map ctx depth o =
  let n = Array.length o / 2 in
  pay ctx n;
  let key = function Text s when Lexer.is_plain_name s -> s | k -> show_at ctx (depth + 1) k in
  "{" ^ String.concat ", " (List.init n (fun i -> key o.(2 * i) ^ ": " ^ show_at ctx (depth + 1) o.((2 * i) + 1))) ^ "}"

(* A struct with one field shows its value only, as the code builds it: Ok(42). More fields show their names. *)
and show_struct ctx depth (shape : shape) fields =
  let names = shape.names in
  let n = Array.length names in
  pay ctx n;
  match shape.sname with
  | Some sname when n = 1 -> sname ^ "(" ^ show_at ctx (depth + 1) fields.(0) ^ ")"
  | sname ->
    let field i = names.(i) ^ " = " ^ show_at ctx (depth + 1) fields.(i) in
    Option.value sname ~default:"" ^ "(" ^ String.concat ", " (List.init n field) ^ ")"

and show_array ctx depth a =
  let cell k = show_at ctx (depth + 1) (elt a k) in
  let n = a.rows * a.cols in
  pay ctx n;
  let numeric () = match (trim a).store with F _ | I _ -> true | V d -> Array.for_all is_number d in
  if n = 0 then "[]"
  else if Array.length a.dims > 0 then show_slices cell a (if numeric () then " " else ", ")
  else if a.rows = 1 then "[" ^ String.concat ", " (List.init n cell) ^ "]"
  else if a.cols = 1 then "[" ^ String.concat "; " (List.init n cell) ^ "]"
  else begin
    let sep = if numeric () then " " else ", " in
    let row i = String.concat sep (List.init a.cols (fun j -> cell ((j * a.rows) + i))) in
    "[" ^ String.concat "; " (List.init a.rows row) ^ "]"
  end

(* Three dimensions or more: each matrix of the first two, as a matrix shows, then ;;; before the next along the third,
   ;;;; along the fourth, and so on, as Julia writes them: [1 3; 2 4;;; 5 7; 6 8] is 2 by 2 by 2. *)
and show_slices cell a sep =
  let r = a.dims.(0) and c = a.dims.(1) in
  let slices = (a.rows * a.cols) / (r * c) in
  let b = Buffer.create 64 in
  Buffer.add_char b '[';
  for s = 0 to slices - 1 do
    if s > 0 then begin
      (* One more ; for each dimension past the second that starts again here. *)
      let rec semis d step = if d < Array.length a.dims - 1 && s mod (step * a.dims.(d)) = 0 then semis (d + 1) (step * a.dims.(d)) else d in
      Buffer.add_string b (String.make (semis 2 1 + 1) ';');
      Buffer.add_char b ' '
    end;
    for i = 0 to r - 1 do
      if i > 0 then Buffer.add_string b "; ";
      for j = 0 to c - 1 do
        if j > 0 then Buffer.add_string b sep;
        Buffer.add_string b (cell ((s * r * c) + (j * r) + i))
      done
    done
  done;
  Buffer.add_char b ']';
  Buffer.contents b

let text_of ctx v = match v with Text s -> s | Int i -> int_text i | _ -> show ctx v

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
    let n = Array.length x.fields in
    x.shape.sname = y.shape.sname && n = Array.length y.fields
    && begin
      pay ctx n;
      let rec go i =
        i >= n
        || begin
          let k = if x.shape == y.shape then i else field_index y.shape x.shape.names.(i) in
          k >= 0 && equal_at ctx (depth + 1) x.fields.(i) y.fields.(k) && go (i + 1)
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
  | Dict { keys = { deep = Flat; _ } as kx; vals = vx; _ }, Dict { keys = { deep = Flat; _ } as ky; vals = vy; _ } when kx == ky && Array.length vx = Array.length vy ->
    let n = Array.length vx in
    pay ctx n;
    let rec go i = i >= n || (equal_at ctx (depth + 1) vx.(i) vy.(i) && go (i + 1)) in
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
