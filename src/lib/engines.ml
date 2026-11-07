open Types

type native = string * int * int * (ctx -> t array -> t)

let suffix = ref (fun () -> "")
let loader = ref (fun (_ : string) -> Error "no plugin in this program")
let registered : native list option ref = ref None
let loading = ref false

(* The engines this process loaded, by file: the fingerprint of the file then, and its natives or why it didn't load. An
   engine never unloads: a run under --watch finds it as the last one left it. *)
let engines : (string, string * (native list, Messages.t) result) Hashtbl.t = Hashtbl.create 4

let register natives =
  if (not !loading) || !registered <> None then invalid_arg (Messages.engine_misuse "register: once, as its engine starts").text;
  registered := Some natives

(* Cesia's own exceptions cross a native untouched: a panic, a limit, sys.Exit, a Cancel, and what the other fibers raise
   while the main program waits in one. Every module named Cesia is Cesia's: no engine may bring one. *)
let own e =
  match e with
  | Value.Kerr _ | Value.Limit _ | Value.Quit _ | Stack_overflow | Out_of_memory -> true
  | _ -> String.starts_with ~prefix:"Cesia" (Printexc.exn_slot_name e)

let names (natives : native list) = List.sort_uniq String.compare (List.map (fun (n, _, _, _) -> n) natives)
let without b a = List.filter (fun n -> not (List.mem n b)) a

(* The engine of a package, at the first call of one of its natives: the permission, then the file, as installed, then the
   plugin of Cesia_v1 and the engine, whose natives must be those of cesia.toml. *)
let link ctx ~label ~folder ~path (p : Package.native) =
  Runtime.check_perm ctx Native (Some label);
  let fail m = Runtime.fail ctx User m in
  let shown = Package.shown path in
  if not (Sys.file_exists path) then begin
    let dir = Filename.dirname path and prefix = p.name ^ "-" in
    let tag n =
      if String.starts_with ~prefix n && Filename.check_suffix n ".cmxs" then
        Some (Filename.chop_suffix (String.sub n (String.length prefix) (String.length n - String.length prefix)) ".cmxs")
      else None
    in
    let found = if Package.is_dir dir then List.filter_map tag (List.sort compare (Array.to_list (Sys.readdir dir))) else [] in
    fail (Messages.engine_missing folder (!suffix ()) found)
  end;
  let src = In_channel.with_open_bin path In_channel.input_all in
  Option.iter fail (Package.unchanged ctx.w.root path src);
  let print = Package.fingerprint src in
  let result =
    match Hashtbl.find_opt engines path with
    | Some (before, _) when before <> print -> fail (Messages.engine_changed shown)
    | Some (_, r) -> r
    | None ->
      loading := true;
      registered := None;
      let loaded = Fun.protect ~finally:(fun () -> loading := false) (fun () -> !loader path) in
      let r =
        match loaded, !registered with
        | Error reason, _ -> Error (Messages.engine_refused shown reason)
        | Ok (), Some natives when names natives = List.sort_uniq String.compare p.natives -> Ok natives
        | Ok (), natives ->
          let got = names (Option.value natives ~default:[]) in
          Error (Messages.engine_names shown (without got p.natives) (without p.natives got))
      in
      Hashtbl.replace engines path (print, r);
      r
  in
  match result with Ok natives -> natives | Error m -> fail m

let stubs ~label ~folder ~path (p : Package.native) =
  (* Linked once per run, for all the natives of the package: each run checks its own permission. *)
  let linked = ref None in
  let table ctx = match !linked with Some t -> t | None -> let t = link ctx ~label ~folder ~path p in linked := Some t; t in
  let stub name =
    let full = p.name ^ "." ^ name in
    let code = ref None in
    let rec run ctx a =
      match !code with
      | Some (fewest, most, f) ->
        let n = Array.length a in
        if n < fewest || n > most then
          Runtime.fail ctx Type
            (Messages.arg_count full (if fewest = most then Printf.sprintf "%d arguments" fewest else Printf.sprintf "%d to %d arguments" fewest most) n);
        (try f ctx a with e when not (own e) -> Runtime.fail ctx User (Messages.native_raised full (Printexc.to_string e)))
      | None ->
        List.iter (fun (n, fewest, most, f) -> if String.equal n name then code := Some (fewest, most, f)) (table ctx);
        run ctx a
    in
    (* The compiler takes the code of a native as it compiles a call, before the engine loads: the stub stays. *)
    name, Native.nat full 0 max_int run
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
