open Cesia

type value = Types.t
type ctx = Types.ctx
type keys = Types.keys

let misuse ctx what = Runtime.fail ctx User (Messages.engine_misuse what)
let missing = Types.Missing
let bool b = if b then Types.True else Types.False
let int i = Types.Int i
let float x = Types.Float x
let text s = Types.Text s

(* The values a package gives may be ones it was given, which the caller still holds: a later write must copy them. *)
let shared a = for i = 0 to Array.length a - 1 do ignore (Value.share a.(i)) done

let list ctx a =
  Runtime.build ctx (Array.length a);
  shared a;
  Arrays.list a

let keys names = Trie.names names

let record ctx (k : keys) a =
  let n = Array.length a in
  if n <> Array.length k.ks then misuse ctx "record: a value for each name of its keys";
  Runtime.build ctx n;
  shared a;
  if n <= Trie.width then Trie.record k a else Trie.of_items (Array.init (2 * n) (fun i -> if i land 1 = 0 then k.ks.(i / 2) else a.(i / 2)))

let handle kind id = Types.Handle { kind; id; task = None }
let ok (ctx : ctx) v = Value.ok ctx.w v
let err (ctx : ctx) v = Value.err ctx.w v

type kind = Missing | Bool | Int | Float | Text | List | Map | Struct | Function | Handle | Other

let kind (v : value) =
  match v with
  | Types.Missing | Types.Undef -> Missing
  | Types.True | Types.False -> Bool
  | Types.Int _ -> Int
  | Types.Float _ -> Float
  | Types.Text _ -> Text
  | Types.Array { rows; cols; dims = [||]; _ } when rows = 1 || rows * cols = 0 -> List
  | Types.Array _ -> Other
  | Types.Dict _ -> Map
  | Types.Struct _ -> Struct
  | Types.Fun _ | Types.Native _ | Types.Bound _ -> Function
  | Types.Handle _ -> Handle

let need ctx name what v = Runtime.fail ctx Type (Messages.native_needs name what (Value.describe v))
let to_bool ctx name v = match v with Types.True -> true | Types.False -> false | v -> need ctx name "a Bool" v
let to_int ctx name v = match v with Types.Int i -> i | v -> need ctx name "an Int" v
let to_float ctx name v = match v with Types.Float x -> x | Types.Int i -> float_of_int i | v -> need ctx name "a Float" v
let to_text ctx name v = match v with Types.Text s -> s | v -> need ctx name "a Text" v

let length v =
  match v with
  | Types.Array { rows; cols; _ } when kind v = List -> rows * cols
  | Types.Dict _ -> Trie.length v
  | Types.Struct { fields; _ } -> Array.length fields
  | _ -> 0

let item ctx v i =
  match v with
  | Types.Array a when kind v = List ->
    if i < 0 || i >= a.rows * a.cols then Runtime.fail ctx Index (Messages.index_outside (i + 1) (a.rows * a.cols));
    Value.share (Value.elt a i)
  | v -> Runtime.fail ctx Type (Messages.index_value (Value.describe v))

let field v name =
  match v with
  | Types.Struct { shape; fields; _ } ->
    let i = Value.field_index shape name in
    if i < 0 then Types.Missing else Value.share fields.(i)
  | Types.Dict _ -> (match Trie.find v (Trie.hash_text name) (Types.Text name) with Types.Undef -> Types.Missing | x -> Value.share x)
  | _ -> Types.Missing

let pairs v =
  match v with
  | Types.Struct { shape; fields; _ } -> List.combine (Array.to_list shape.names) (Array.to_list fields)
  | Types.Dict _ ->
    let items = Trie.items v in
    List.filter_map
      (fun i -> match items.(2 * i) with Types.Text k -> Some (k, items.((2 * i) + 1)) | _ -> None)
      (List.init (Array.length items / 2) Fun.id)
  | _ -> []

let names v = Array.of_list (List.map fst (pairs v))
let values v = Array.of_list (List.map (fun (_, x) -> Value.share x) (pairs v))

let handle_id ctx name kind v =
  match v with Types.Handle { kind = k; id; _ } when String.equal k kind -> id | v -> need ctx name ("a handle " ^ kind) v

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

let register natives =
  if not (Domain.is_main_domain ()) then invalid_arg (Messages.engine_misuse "register: on Cesia's domain only").text;
  Cesia_link.register natives
