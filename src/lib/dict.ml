open Types

let compare_keys = Trie.compare_keys

let is_key = function
  | Int _ | Text _ -> true
  | Float x -> not (Float.is_nan x)
  | _ -> false

let check ctx k = if not (is_key k) then Runtime.fail ctx Type (Messages.dict_key (Value.describe k))
let length = Trie.length

let find ctx k d =
  check ctx k;
  match Trie.tree_find k d with Undef -> None | v -> Some v

let add ctx k v d =
  check ctx k;
  Trie.tree_insert k v 0 d

let empty () = Trie.empty ()

let of_items ctx (a : t array) =
  let n = Array.length a / 2 in
  for i = 0 to n - 1 do
    check ctx a.(2 * i)
  done;
  Trie.of_items (if Array.length a = 2 * n then a else Array.sub a 0 (2 * n))

let not_map ctx name v =
  match v with
  | Struct { shape = { sname = Some sn; _ }; _ } -> Runtime.fail ctx Type (Messages.map_of_struct name sn)
  | _ -> Runtime.fail ctx Type (Messages.need_dict name (Value.describe v))

let get ctx name k m =
  match m with
  | Dict _ ->
    check ctx k;
    (match Trie.find m (Trie.hash k) k with Undef -> None | v -> Some v)
  | _ -> not_map ctx name m

let put ctx name k v m =
  match m with
  | Dict _ ->
    check ctx k;
    Trie.put m (Trie.hash k) k v
  | _ -> not_map ctx name m

let drop ctx name k m =
  match m with
  | Dict _ ->
    check ctx k;
    Trie.drop m (Trie.hash k) k
  | _ -> not_map ctx name m

let add_name ctx m name x = put ctx "" (Text name) x m

let items ctx name m =
  match m with
  | Dict _ -> Trie.items m
  | _ -> not_map ctx name m
