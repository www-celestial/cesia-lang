open Types

exception Kerr of { kind : kind; text : string; hint : string option; at : int }
exception Limit of { what : string; at : int }

let of_bool b = if b then True else False

let rec dict_fold f d acc =
  match d with
  | Leaf -> acc
  | Node n -> dict_fold f n.l (f n.k n.v (dict_fold f n.r acc))

let share v =
  (match v with
   | Array a -> a.a_owned <- false
   | Struct r -> r.r_owned <- false
   | _ -> ());
  v

let kind_name = function
  | Syntax -> "syntax"
  | Name -> "name"
  | Type -> "type"
  | Index -> "index"
  | Field -> "field"
  | Overflow -> "overflow"
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
  String.iter (fun c -> if c = '"' then Buffer.add_string b "\"\"" else Buffer.add_char b c) s;
  Buffer.add_char b '"';
  Buffer.contents b

let elt a k =
  match a.store with
  | F d -> Float (Float.Array.get d k)
  | I d -> Int d.(k)
  | V d -> d.(k)

(* The free cells behind a list stay behind: this is for code that reads a store as a whole. *)
let trim a =
  let n = a.rows * a.cols in
  (match a.store with
   | F d -> if Float.Array.length d <> n then a.store <- F (Float.Array.sub d 0 n)
   | I d -> if Array.length d <> n then a.store <- I (Array.sub d 0 n)
   | V d -> if Array.length d <> n then a.store <- V (Array.sub d 0 n));
  a

let is_number = function Int _ | Float _ -> true | _ -> false

let shape_of w ?sname names =
  let key = match sname with Some n -> Array.append [| "#" ^ n |] names | None -> names in
  match Hashtbl.find_opt w.shapes key with
  | Some s -> s
  | None ->
    let s = { sid = Hashtbl.length w.shapes; names; sname; next = Hashtbl.create 4 } in
    Hashtbl.add w.shapes key s;
    s

let field_index shape name =
  let n = Array.length shape.names in
  let rec go i = if i >= n then -1 else if String.equal shape.names.(i) name then i else go (i + 1) in
  go 0

let add_field w (shape : shape) fields name x =
  let next =
    match Hashtbl.find_opt shape.next name with
    | Some s -> s
    | None ->
      let s = shape_of w (Array.append shape.names [| name |]) in
      Hashtbl.add shape.next name s;
      s
  in
  Struct { shape = next; fields = Array.append fields [| x |]; r_owned = true }

let result w sname field v =
  Struct { shape = shape_of w ~sname [| field |]; fields = [| share v |]; r_owned = true }

let ok w v = result w "Ok" "value" v
let err w v = result w "Err" "error" v

let failure w kind text =
  let shape = shape_of w [| "kind"; "message" |] in
  err w (Struct { shape; fields = [| Text kind; Text text |]; r_owned = true })

let nested ctx depth =
  if depth > ctx.w.limits.nesting then raise (Limit { what = "nesting"; at = -1 })

(* Showing and comparing are natives: they count their steps, otherwise a highly shared value, which fits in little
   memory, would escape --limit steps. *)
let pay ctx n = ctx.w.charge ctx ((n / 16) + 1)

let rec show ctx v = show_at ctx 0 v

and show_at ctx depth v =
  nested ctx depth;
  match v with
  | Missing -> "missing"
  | Undef -> "undefined"
  | True -> "true"
  | False -> "false"
  | Int i -> string_of_int i
  | Float x -> float_text x
  | Text s -> quote s
  | Array a -> show_array ctx depth a
  | Struct r -> show_struct ctx depth r.shape r.fields
  | Fun c -> "function " ^ c.proto.pname
  | Native n -> "function " ^ n.nname
  | Handle h -> Printf.sprintf "<%s %d>" h.kind h.id
  | Dict d -> show_dict ctx depth d

and show_dict ctx depth d =
  let pairs = dict_fold (fun k v rest -> (k, v) :: rest) d [] in
  pay ctx (List.length pairs);
  match pairs with
  | [] -> "dict()"
  | _ ->
    let item (k, v) = show_at ctx (depth + 1) k ^ ": " ^ show_at ctx (depth + 1) v in
    "{" ^ String.concat ", " (List.map item pairs) ^ "}"

and show_struct ctx depth (shape : shape) fields =
  let names = shape.names in
  let field sep i = names.(i) ^ sep ^ show_at ctx (depth + 1) fields.(i) in
  let n = Array.length names in
  pay ctx n;
  match shape.sname with
  | None -> "{" ^ String.concat ", " (List.init n (field ": ")) ^ "}"
  | Some s -> s ^ "(" ^ String.concat ", " (List.init n (field " = ")) ^ ")"

and show_array ctx depth a =
  let cell k = show_at ctx (depth + 1) (elt a k) in
  let n = a.rows * a.cols in
  pay ctx n;
  if n = 0 then "[]"
  else if a.rows = 1 then "[" ^ String.concat ", " (List.init n cell) ^ "]"
  else if a.cols = 1 then "[" ^ String.concat "; " (List.init n cell) ^ "]"
  else begin
    let numeric = match (trim a).store with F _ | I _ -> true | V d -> Array.for_all is_number d in
    let sep = if numeric then " " else ", " in
    let row i = String.concat sep (List.init a.cols (fun j -> cell ((j * a.rows) + i))) in
    "[" ^ String.concat "; " (List.init a.rows row) ^ "]"
  end

let text_of ctx v = match v with Text s -> s | _ -> show ctx v

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
  | Struct _ -> "a struct"
  | Fun c -> "function " ^ c.proto.pname
  | Native n -> "function " ^ n.nname
  | Handle h -> "a " ^ h.kind
  | Dict _ -> "a dictionary"
  | Undef -> "an undefined value"

let rec equal ctx a b = equal_at ctx 0 a b

and equal_at ctx depth a b =
  nested ctx depth;
  match a, b with
  | Array x, Array y ->
    (x.rows * x.cols = 0 && y.rows * y.cols = 0)
    || x.rows = y.rows && x.cols = y.cols
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
  | Dict x, Dict y ->
    let items d = dict_fold (fun k v rest -> (k, v) :: rest) d [] in
    let xs = items x and ys = items y in
    pay ctx (List.length xs);
    List.compare_lengths xs ys = 0
    && List.for_all2
         (fun (a, b) (c, d) -> equal_at ctx (depth + 1) a c && equal_at ctx (depth + 1) b d)
         xs ys
  | _ -> false
