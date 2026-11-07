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

let four = C.keys [| "Int"; "Float"; "Text"; "Bool" |]

let echo4 ctx a =
  let name = "echo.Echo4" in
  C.record ctx four
    [| C.int (C.to_int ctx name a.(0)); C.float (C.to_float ctx name a.(1)); C.text (C.to_text ctx name a.(2));
       C.bool (C.to_bool ctx name a.(3)) |]

let kind_name = function
  | C.Missing -> "missing" | Bool -> "bool" | Int -> "int" | Float -> "float" | Text -> "text" | List -> "list"
  | Map -> "map" | Struct -> "struct" | Function -> "function" | Handle -> "handle" | Other -> "other"

let kind_of _ a = C.text (kind_name (C.kind a.(0)))
let reverse ctx a = let v = a.(0) and n = C.length a.(0) in C.list ctx (Array.init n (fun i -> C.item ctx v (n - 1 - i)))

(* A map of the same fields, and one more, Count, the number of them. *)
let fields ctx a =
  let names = C.names a.(0) and values = C.values a.(0) in
  C.record ctx (C.keys (Array.append names [| "Count" |])) (Array.append values [| C.int (C.length a.(0)) |])

let field ctx a = C.field a.(0) (C.to_text ctx "echo.Field" a.(1))
let thing ctx a = C.handle "echo.thing" (C.to_int ctx "echo.Thing" a.(0))
let number ctx a = C.int (C.handle_id ctx "echo.Number" "echo.thing" a.(0))
let boom _ _ = raise Not_found
let refuse ctx a = C.panic ctx ("echo.Refuse: " ^ C.to_text ctx "echo.Refuse" a.(0))
let read ctx a = C.need_read ctx (C.to_text ctx "echo.Read" a.(0)); C.ok ctx C.missing

(* Waits on a domain of its own, which wakes the fiber: the others run meanwhile. *)
let later ctx a =
  let seconds = C.to_float ctx "echo.Later" a.(0) in
  C.suspend ctx (fun resume -> ignore (Domain.spawn (fun () -> Unix.sleepf seconds; resume ())));
  C.ok ctx a.(1)

let () =
  C.register
    [ "echo4", 4, 4, echo4; "kindOf", 1, 1, kind_of; "reverse", 1, 1, reverse; "fields", 1, 1, fields;
      "field", 2, 2, field; "thing", 1, 1, thing; "number", 1, 1, number; "boom", 0, 0, boom; "refuse", 1, 1, refuse;
      "read", 1, 1, read; "later", 2, 2, later ]
