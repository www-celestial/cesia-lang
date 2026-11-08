open Types

(* One walk for math.Near and for the first difference that a failed test shows: with [tol], numbers within it are the same. *)

type tol = { rel : float; abs : float }

let number = function Int i -> Some (float_of_int i) | Float x -> Some x | _ -> None

(* |a - b| <= max(rel * max(|a|, |b|), abs): equal infinities are near, NaN is near nothing. *)
let close t a b =
  a = b
  || Float.is_finite a && Float.is_finite b
     && Float.abs (a -. b) <= Float.max (t.rel *. Float.max (Float.abs a) (Float.abs b)) t.abs

(* The position of cell [k], column by column: one for a list, one per dimension otherwise. *)
let index (x : arr) k =
  if x.rows = 1 && Array.length x.dims = 0 then Printf.sprintf "[%d]" (k + 1)
  else begin
    let rest = ref k in
    let at n = let i = (!rest mod n) + 1 in rest := !rest / n; string_of_int i in
    "[" ^ String.concat ", " (Array.to_list (Array.map at (Arrays.sizes x))) ^ "]"
  end

let key ctx = function
  | Text s when s <> "" && Lexer.is_public s && String.for_all (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> true | _ -> false) s -> "." ^ s
  | k -> "[" ^ Value.show ctx k ^ "]"

(** Where two values first differ, from the outside in: the path, and the two values there, or [None] when they are equal,
    or near with [tol]. A path of "" is the values themselves. *)
let rec first ctx ?tol a b = walk ctx tol 0 "" a b

and walk ctx tol depth path a b =
  Value.nested ctx depth;
  let here () = Some (path, a, b) in
  match a, b, tol with
  | (Int _ | Float _), (Int _ | Float _), Some t ->
    (match number a, number b with Some x, Some y when close t x y -> None | _ -> here ())
  | Array x, Array y, _ when x.rows * x.cols > 0 || y.rows * y.cols > 0 ->
    if not (Value.same_shape x y) then here ()
    else begin
      let n = x.rows * x.cols in
      Value.pay ctx n;
      match x.store, y.store, tol with
      | F p, F q, Some t ->
        let rec go k =
          if k >= n then None
          else if close t (Float.Array.get p k) (Float.Array.get q k) then go (k + 1)
          else Some (path ^ index x k, Value.elt x k, Value.elt y k)
        in
        go 0
      | _ ->
        let rec go k = if k >= n then None else match walk ctx tol (depth + 1) (path ^ index x k) (Value.elt x k) (Value.elt y k) with None -> go (k + 1) | d -> d in
        go 0
    end
  | Struct x, Struct y, _ when x.shape.sname = y.shape.sname && Trie.nvals x.fields = Trie.nvals y.fields ->
    let n = Trie.nvals x.fields in
    Value.pay ctx n;
    let rec go i =
      if i >= n then None
      else
        let k = Value.field_index y.shape x.shape.names.(i) in
        if k < 0 then here ()
        else match walk ctx tol (depth + 1) (path ^ "." ^ x.shape.names.(i)) (Trie.vget x.fields i) (Trie.vget y.fields k) with None -> go (i + 1) | d -> d
    in
    go 0
  | Dict _, Dict _, _ ->
    let o = Trie.items a and p = Trie.items b in
    Value.pay ctx (Array.length o + Array.length p);
    (* A key of a that b lacks, or that differs, then a key of b that a lacks. *)
    let rec go o other i flip =
      if 2 * i >= Array.length o then None
      else
        let k = o.(2 * i) in
        let y = Trie.find other (Trie.hash k) k in
        let y = if y == Undef then Missing else y in
        let d = if flip then walk ctx tol (depth + 1) (path ^ key ctx k) y o.((2 * i) + 1) else walk ctx tol (depth + 1) (path ^ key ctx k) o.((2 * i) + 1) y in
        if Option.is_none d then go o other (i + 1) flip else d
    in
    (match go o b 0 false with
     | None -> (match go p a 0 true with None when Array.length o <> Array.length p -> here () | d -> d)
     | d -> d)
  | _ -> if Value.equal ctx a b then None else here ()

let float_arg ctx name v default =
  match v with
  | Undef | Missing -> default
  | Int i when i >= 0 -> float_of_int i
  | Float x when x >= 0. -> x
  | _ -> Runtime.fail ctx Type (Messages.near_tolerance name (Value.describe v))

(** The tolerance of a call to math.Near, from its rel and abs arguments. *)
let tol_of ctx rel abs = { rel = float_arg ctx "rel" rel 1e-9; abs = float_arg ctx "abs" abs 0. }

let near ctx (a : t array) =
  let arg i = if Array.length a > i then a.(i) else Undef in
  Value.of_bool (first ctx ~tol:(tol_of ctx (arg 2) (arg 3)) a.(0) a.(1) = None)

let natives = [ "Near", Native.nat ~params:[| "a"; "b"; "rel"; "abs" |] "Near" 2 4 near ]
