open Types

let suffix = ref (fun () -> "")
let interface = ref (fun () -> Error "no plugin in this program")
let link = ref (fun (_ : ctx) ~label:(_ : string) ~folder:(_ : string) ~path:(_ : string) (_ : Package.native) -> [])

(* The compiler takes the code of a native as it compiles a call, before the engine loads: each stub stays, and calls the
   native that the plugin of Cesia_v1 links at the first call of one of them, once per run. *)
let stubs ~label ~folder ~path (p : Package.native) =
  let linked = ref None in
  let table ctx =
    match !linked with
    | Some t -> t
    | None ->
      (match !interface () with Ok () -> () | Error m -> Runtime.fail ctx User (Messages.engine_refused (Package.shown path) m));
      let t = !link ctx ~label ~folder ~path p in
      linked := Some t;
      t
  in
  let stub name =
    let code = ref None in
    let rec run ctx a = match !code with Some f -> f ctx a | None -> code := Some (List.assoc name (table ctx)); run ctx a in
    name, Native.nat (p.name ^ "." ^ name) 0 max_int run
  in
  List.map stub p.natives

let natives w dir =
  let folder = match Package.installed w.root dir with Some f when String.starts_with ~prefix:"deps/" f -> f | _ -> "" in
  let root = if folder = "" then w.root else Filename.concat w.root folder in
  match Package.native root with
  | Some p when String.equal p.package (Package.absolute dir) ->
    let path = Filename.concat root (Printf.sprintf "native/%s-%s.cmxs" p.name (!suffix ())) in
    let label = if folder = "" then p.name else Option.value (Package.label w.root folder) ~default:p.name in
    Some (stubs ~label ~folder ~path p)
  | _ -> None

let cesia = [ "Native", Native.nat "cesia.Native" 0 0 (fun _ _ -> Text (!suffix ())) ]
