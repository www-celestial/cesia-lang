open Cesia

type ctx = Types.ctx
type keys = Types.keys
type compound = Types.t

type value =
  | Missing | Bool of bool | Int of int | Float of float | Text of string | Handle of string * int
  | List of compound | Map of compound | Struct of compound | Function of compound | Other of compound

let misuse ctx what = Runtime.fail ctx User (Messages.engine_misuse what)

(* A value that a package gives back may be one it was given, which the caller still holds: a later write must copy it, so
   every compound is shared on its way back, none on its way in. *)
let[@inline] of_value v =
  match v with
  | Missing -> Types.Missing
  | Bool b -> if b then Types.True else Types.False
  | Int i -> Types.Int i
  | Float x -> Types.Float x
  | Text s -> Types.Text s
  | Handle (kind, id) -> Types.Handle { kind; id; task = None }
  | List c | Map c | Struct c | Function c | Other c -> Value.share c

let is_list (a : Types.arr) = Array.length a.dims = 0 && (a.rows = 1 || a.rows * a.cols = 0)

let[@inline] to_value (v : Types.t) =
  match v with
  | Types.Missing | Types.Undef -> Missing
  | Types.True -> Bool true
  | Types.False -> Bool false
  | Types.Int i -> Int i
  | Types.Float x -> Float x
  | Types.Text s -> Text s
  | Types.Handle { kind; id; task = None } -> Handle (kind, id)
  | Types.Array a when is_list a -> List v
  | Types.Dict _ -> Map v
  | Types.Struct _ -> Struct v
  | Types.Fun _ | Types.Native _ | Types.Bound _ -> Function v
  | Types.Array _ | Types.Handle _ -> Other v

(* Up to 6 values, the array is made inline: Array.map would call C to make it. *)
let[@inline] of_values a =
  match a with
  | [||] -> [||]
  | [| a0 |] -> [| of_value a0 |]
  | [| a0; a1 |] -> [| of_value a0; of_value a1 |]
  | [| a0; a1; a2 |] -> [| of_value a0; of_value a1; of_value a2 |]
  | [| a0; a1; a2; a3 |] -> [| of_value a0; of_value a1; of_value a2; of_value a3 |]
  | [| a0; a1; a2; a3; a4 |] -> [| of_value a0; of_value a1; of_value a2; of_value a3; of_value a4 |]
  | [| a0; a1; a2; a3; a4; a5 |] -> [| of_value a0; of_value a1; of_value a2; of_value a3; of_value a4; of_value a5 |]
  | _ -> Array.map of_value a

let to_values a =
  match a with
  | [||] -> [||]
  | [| a0 |] -> [| to_value a0 |]
  | [| a0; a1 |] -> [| to_value a0; to_value a1 |]
  | [| a0; a1; a2 |] -> [| to_value a0; to_value a1; to_value a2 |]
  | [| a0; a1; a2; a3 |] -> [| to_value a0; to_value a1; to_value a2; to_value a3 |]
  | [| a0; a1; a2; a3; a4 |] -> [| to_value a0; to_value a1; to_value a2; to_value a3; to_value a4 |]
  | [| a0; a1; a2; a3; a4; a5 |] -> [| to_value a0; to_value a1; to_value a2; to_value a3; to_value a4; to_value a5 |]
  | _ -> Array.map to_value a

let list ctx a =
  Runtime.build ctx (Array.length a);
  List (Arrays.list (of_values a))

let keys names =
  let sorted = List.sort String.compare (Array.to_list names) in
  if List.length (List.sort_uniq String.compare sorted) <> List.length sorted then
    invalid_arg (Messages.engine_misuse "keys: each name once").text;
  Trie.names names

let record ctx (k : keys) a =
  let n = Array.length a in
  if n <> Array.length k.ks then misuse ctx "record: a value for each name of its keys";
  Runtime.build ctx n;
  let vals = of_values a in
  Map (if n <= Trie.width then Trie.record k vals else Trie.of_items (Array.init (2 * n) (fun i -> if i land 1 = 0 then k.ks.(i / 2) else vals.(i / 2))))

let ok (ctx : ctx) v = Struct (Value.ok ctx.w (of_value v))
let err (ctx : ctx) v = Struct (Value.err ctx.w (of_value v))

let length (c : compound) =
  match c with
  | Types.Array ({ rows; cols; _ } as a) when is_list a -> rows * cols
  | Types.Dict _ -> Trie.length c
  | Types.Struct { fields; _ } -> Trie.nvals fields
  | _ -> 0

let item ctx (c : compound) i =
  match c with
  | Types.Array a when is_list a ->
    if i < 0 || i >= a.rows * a.cols then Runtime.fail ctx Index (Messages.index_outside (i + 1) (a.rows * a.cols));
    to_value (Value.elt a i)
  | v -> Runtime.fail ctx Type (Messages.index_value (Value.describe v))

(* A map's fields by their hashes, its first ones made inline; a struct's by their names. *)
let[@inline] find c h key = to_value (Trie.find c h key)

let fields (k : keys) c =
  match c, k.hs, k.ks with
  | Types.Dict _, [| h0 |], [| k0 |] -> [| find c h0 k0 |]
  | Types.Dict _, [| h0; h1 |], [| k0; k1 |] -> [| find c h0 k0; find c h1 k1 |]
  | Types.Dict _, [| h0; h1; h2 |], [| k0; k1; k2 |] -> [| find c h0 k0; find c h1 k1; find c h2 k2 |]
  | Types.Dict _, [| h0; h1; h2; h3 |], [| k0; k1; k2; k3 |] -> [| find c h0 k0; find c h1 k1; find c h2 k2; find c h3 k3 |]
  | Types.Dict _, hs, ks -> Array.init (Array.length hs) (fun i -> find c hs.(i) ks.(i))
  | Types.Struct { shape; fields; _ }, _, ks ->
    let get key = match key with Types.Text n -> let j = Value.field_index shape n in if j < 0 then Missing else to_value (Trie.vget fields j) | _ -> Missing in
    Array.map get ks
  | _, _, ks -> Array.make (Array.length ks) Missing

let pairs (c : compound) =
  match c with
  | Types.Struct { shape; fields; _ } -> List.combine (Array.to_list shape.names) (Array.to_list (Trie.vals_array fields))
  | Types.Dict _ ->
    let items = Trie.items c in
    List.filter_map
      (fun i -> match items.(2 * i) with Types.Text k -> Some (k, items.((2 * i) + 1)) | _ -> None)
      (List.init (Array.length items / 2) Fun.id)
  | _ -> []

let names c = Array.of_list (List.map fst (pairs c))
let values c = Array.of_list (List.map (fun (_, x) -> to_value x) (pairs c))
let need ctx name what v = Runtime.fail ctx Type (Messages.native_needs name what (Value.describe (of_value v)))

(* The function runs in the scheduler, where an exception would stop the program: it wakes the fiber, which raises it. *)
let suspend (ctx : ctx) f =
  if not (Domain.is_main_domain ()) then misuse ctx "suspend: on Cesia's domain only";
  let raised = ref None in
  Fiber.suspend ctx (fun wake ->
      let resume = ctx.w.remote wake in
      try f resume with e -> raised := Some e; resume ());
  Option.iter raise !raised

let need_read ctx path = Runtime.check_perm ctx Read (Some path)
let need_write ctx path = Runtime.check_perm ctx Write (Some path)
let panic ctx text = Runtime.fail ctx User (Messages.plain text)
let pay = Runtime.pay
let reserve = Runtime.reserve

(* A native takes its arguments and gives its result as values: the stub's own pass through Cesia's layout. *)
let register natives =
  if not (Domain.is_main_domain ()) then invalid_arg (Messages.engine_misuse "register: on Cesia's domain only").text;
  Cesia_link.register (List.map (fun (name, fewest, most, f) -> name, fewest, most, fun ctx a -> of_value (f ctx (to_values a))) natives)
