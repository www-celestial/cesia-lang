(* The engine of the tests of native packages, built as the author of a package builds one: against cesia_v1.cmi alone,
   with the Stdlib and Unix that Cesia's binary holds. *)
module C = Cesia_v1

(* Each module of the Stdlib and of Unix that the binary holds, which an engine may use: a Cesia that lost one would refuse
   this engine, and name the module. *)
module M = Map.Make (String)

let _held =
  ( (Array.length, Atomic.make, Bigarray.Array1.dim, Buffer.create, Bytes.create, Callback.register, Char.code),
    (Condition.create, Digest.string, Domain.self, Effect.perform, Filename.concat, Float.abs, Fun.id),
    (Gc.minor, Hashtbl.hash, In_channel.input_all, Int.abs, Lazy.force, List.length, M.empty, Mutex.create, Nativeint.add),
    (Obj.repr, Option.is_some, Out_channel.flush, Printexc.to_string, Printf.sprintf, Queue.create, Random.int),
    (Result.is_ok, Seq.empty, String.length, Sys.time, Uchar.of_int, Unix.sleepf, UnixLabels.sleepf, Stdlib.print_string),
    (CamlinternalFormat.make_printf, CamlinternalFormatBasics.concat_fmt, CamlinternalLazy.force_lazy_block) )

(* The engine's own readers of arguments: a match each, no call to Cesia, and Cesia's message for a wrong one. *)
let int ctx name = function C.Int i -> i | v -> C.need ctx name "an Int" v
let float ctx name = function C.Float x -> x | C.Int i -> float_of_int i | v -> C.need ctx name "a Float" v
let text ctx name = function C.Text s -> s | v -> C.need ctx name "a Text" v
let bool ctx name = function C.Bool b -> b | v -> C.need ctx name "a Bool" v

let four = C.keys [| "Int"; "Float"; "Text"; "Bool" |]

let echo4 ctx a =
  let name = "echo.Echo4" in
  C.record ctx four
    [| Int (int ctx name a.(0)); Float (float ctx name a.(1)); Text (text ctx name a.(2)); Bool (bool ctx name a.(3)) |]

let kind_name = function
  | C.Missing -> "missing" | Bool _ -> "bool" | Int _ -> "int" | Float _ -> "float" | Text _ -> "text" | List _ -> "list"
  | Map _ -> "map" | Struct _ -> "struct" | Function _ -> "function" | Handle _ -> "handle" | Other _ -> "other"

let kind_of _ a = C.Text (kind_name a.(0))

let reverse ctx a =
  match a.(0) with
  | C.List l -> let n = C.length l in C.list ctx (Array.init n (fun i -> C.item ctx l (n - 1 - i)))
  | v -> C.need ctx "echo.Reverse" "a list" v

(* A map of the same fields, and one more, Count, the number of them. *)
let fields ctx a =
  match a.(0) with
  | C.Map m | C.Struct m ->
    C.record ctx (C.keys (Array.append (C.names m) [| "Count" |])) (Array.append (C.values m) [| Int (C.length m) |])
  | v -> C.need ctx "echo.Fields" "a map or a struct" v

let field ctx a =
  match a.(0) with
  | C.Map m | C.Struct m -> (C.fields (C.keys [| text ctx "echo.Field" a.(1) |]) m).(0)
  | _ -> C.Missing

let thing ctx a = C.Handle ("echo.thing", int ctx "echo.Thing" a.(0))
let number ctx a = match a.(0) with C.Handle ("echo.thing", n) -> C.Int n | v -> C.need ctx "echo.Number" "a handle echo.thing" v
let same _ a = a.(0)
let boom _ _ = raise Not_found
let refuse ctx a = C.panic ctx ("echo.Refuse: " ^ text ctx "echo.Refuse" a.(0))
let read ctx a = C.need_read ctx (text ctx "echo.Read" a.(0)); C.ok ctx C.Missing

(* Waits on a domain of its own, which wakes the fiber: the others run meanwhile. *)
let later ctx a =
  let seconds = float ctx "echo.Later" a.(0) in
  C.suspend ctx (fun resume -> ignore (Domain.spawn (fun () -> Unix.sleepf seconds; resume ())));
  C.ok ctx a.(1)

let () =
  C.register
    [ "echo4", 4, 4, echo4; "kindOf", 1, 1, kind_of; "reverse", 1, 1, reverse; "fields", 1, 1, fields;
      "field", 2, 2, field; "thing", 1, 1, thing; "number", 1, 1, number; "boom", 0, 0, boom; "refuse", 1, 1, refuse;
      "read", 1, 1, read; "later", 2, 2, later; "same", 4, 4, same ]
