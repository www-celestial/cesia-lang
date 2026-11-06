open Types

let register_file w path src =
  Dynarray.add_last w.files (path, src);
  Dynarray.length w.files - 1

let source_of w path =
  let found = ref None in
  Dynarray.iter (fun (p, s) -> if String.equal p path then found := Some s) w.files;
  !found

(* Line [n], without line ending or BOM. *)
let line_text src n =
  let src = if String.starts_with ~prefix:"\xef\xbb\xbf" src then String.sub src 3 (String.length src - 3) else src in
  match List.nth_opt (String.split_on_char '\n' src) (n - 1) with
  | None -> None
  | Some l ->
    let k = String.length l in
    Some (if k > 0 && l.[k - 1] = '\r' then String.sub l 0 (k - 1) else l)

(* The ^ line copies the tabs, to stay aligned. *)
let caret_prefix line col =
  let b = Buffer.create col in
  let seen = ref 1 in
  String.iter
    (fun c ->
       if !seen < col && Char.code c land 0xC0 <> 0x80 then begin
         Buffer.add_char b (if c = '\t' then '\t' else ' ');
         incr seen
       end)
    line;
  while !seen < col do
    Buffer.add_char b ' ';
    incr seen
  done;
  Buffer.contents b

let format_error ~source ~path ~pos ~text ~hint ~trace =
  let b = Buffer.create 256 in
  let line = Pos.line pos and col = Pos.col pos in
  Buffer.add_string b (Printf.sprintf "%s:%d:%d: %s\n" path line col text);
  (match source with
   | Some src when String.is_valid_utf_8 src ->
     (match line_text src line with
      | Some l ->
        let num = string_of_int line in
        Buffer.add_string b (Printf.sprintf "  %s | %s\n" num l);
        Buffer.add_string b (Printf.sprintf "  %s | %s^\n" (String.make (String.length num) ' ') (caret_prefix l col))
      | None -> ())
   | _ -> ());
  (match hint with Some h -> Buffer.add_string b ("  " ^ h ^ "\n") | None -> ());
  List.iter (fun t -> Buffer.add_string b ("  " ^ t ^ "\n")) trace;
  Buffer.contents b

let add_module w md =
  w.modules <- Array.append w.modules [| md |];
  Array.length w.modules - 1

let in_module w m name =
  let md = w.modules.(m) in
  match List.find_map (fun (n, k) -> if String.equal n name then Some k else None) md.mnames with
  | Some k -> Some (Ast.Cell { m; k; stable = md.stable.(k) })
  | None -> None

let in_package w m name = Array.find_map (fun k -> in_module w k name) w.modules.(m).package

(* No name is global: a file sees its package and its uses. Only the parser writes a # name, as the #dict of a dictionary
   literal, which module 0 holds. *)
let lookup w name = if name <> "" && name.[0] = '#' then in_module w 0 name else None

(* What the natives of a package and [lookup] give: the names a file of a package of std/ sees beyond its own files, small
   ones too. *)
let with_natives w natives name =
  match Array.find_map (fun k -> if w.modules.(k).path = "" then in_module w k name else None) natives with
  | Some b -> Some b
  | None -> lookup w name

let message_of_error = function
  | Pos.Load_error { text; _ } -> Some text
  | Value.Kerr { text; _ } -> Some text
  | Value.Limit { what; _ } -> Some (Messages.limit what).text
  | Stack_overflow -> Some (Messages.limit "depth").text
  | Out_of_memory -> Some (Messages.limit "memory").text
  | _ -> None

let std_source name =
  match Sys.getenv_opt "CESIA_STD" with
  | Some dir ->
    let path = Filename.concat dir (name ^ Package.suffix) in
    if Sys.file_exists path then Some (path, In_channel.with_open_bin path In_channel.input_all) else None
  | None ->
    Option.map (fun src -> "std/" ^ name ^ Package.suffix, src) (List.assoc_opt name Embedded.files)

let use_error ~file ~pos ~kind (m : Messages.t) =
  raise (Pos.Load_error { file; pos; kind; text = m.text; hint = m.hint })

let read_module ~from ~pos upath path =
  try In_channel.with_open_bin path In_channel.input_all
  with Sys_error _ -> use_error ~file:from ~pos ~kind:"name" (Messages.use_unreadable upath)


(* A library of Cesia: a module of std/ that isn't the language itself. *)
let own_library name = if List.mem name Docs.language then None else std_source name

(* What comes with Cesia is used through std/: std/sys, a module of the binary, or std/rope, a library. Gives its name. *)
let standard upath =
  match String.split_on_char '/' upath with
  | [ "std"; name ] when name <> "" -> Some name
  | _ -> None

let libraries () = List.filter_map (fun (name, _) -> Option.map (fun (_, src) -> name, src) (own_library name)) Embedded.files

(* A file of std/ or deps/ loads only as installed: its fingerprint in cesia.lock, on a text read anyway. *)
let check_installed w ~from ~pos path src =
  match Package.installed w.root path with
  | None -> ()
  | Some folder ->
    let lock = Package.lock w.root in
    let path = Package.absolute path in
    let from_root p = String.sub p (String.length w.root + 1) (String.length p - String.length w.root - 1) in
    match Hashtbl.find_opt lock path with
    | Some print when String.equal print (Tooling.fingerprint src) -> ()
    | Some _ -> use_error ~file:from ~pos ~kind:"name" (Messages.changed_by_hand (from_root path))
    | None ->
      let inside = Filename.concat w.root folder ^ "/" in
      if Hashtbl.fold (fun p _ seen -> seen || String.starts_with ~prefix:inside p) lock false then
        use_error ~file:from ~pos ~kind:"name" (Messages.changed_by_hand (from_root path))
      else use_error ~file:from ~pos ~kind:"name" (Messages.not_installed folder)

let reader w ~from ~pos upath files () =
  List.map
    (fun path ->
       let src = read_module ~from ~pos upath path in
       check_installed w ~from ~pos path src;
       Package.shown path, src)
    files

(* What a use names, without loading it: a library, the project's copy in std/ or else Cesia's own, or a folder of the project.
   Gives its key in [w.loaded], how to read its files, and whether it is a library. *)
let locate w ~from ~pos upath =
  let missing dir =
    use_error ~file:from ~pos ~kind:"name" (if Package.is_dir dir then Messages.use_empty upath else Messages.use_missing upath)
  in
  (* A wrong cesia.toml stops the first use, before any library runs. *)
  ignore (Package.sources w.root);
  (* The forms of before 0.3: pkg/rope, rope, sys. *)
  let old = if String.starts_with ~prefix:"pkg/" upath then String.sub upath 4 (String.length upath - 4) else upath in
  if (not (String.contains old '/')) && (own_library old <> None || List.mem_assoc old w.native_modules)
     && Package.files (Filename.concat w.root upath) = [] then
    use_error ~file:from ~pos ~kind:"name" (Messages.use_std old);
  match standard upath with
  | Some name ->
    let dir = Filename.concat (Filename.concat w.root "std") name in
    (match Package.files dir with
     | _ :: _ as files -> dir, reader w ~from ~pos upath files, true
     | [] ->
       match own_library name with
       | Some ((path, _) as source) -> path, (fun () -> [ source ]), true
       | None -> missing dir)
  | None ->
    let root, path =
      match Package.dep upath with
      | Some (project, package) ->
        let root = Filename.concat w.root project in
        if not (Sys.file_exists (Filename.concat root Package.project_file)) then
          use_error ~file:from ~pos ~kind:"name" (Messages.not_installed project);
        root, package
      | None when String.starts_with ~prefix:"deps/" upath -> use_error ~file:from ~pos ~kind:"name" (Messages.use_dep upath)
      | None ->
        (* The code of a project in deps/ reads its own project, from its root and its source folders. *)
        (match Package.installed w.root from with
         | Some folder when String.starts_with ~prefix:"deps/" folder -> Filename.concat w.root folder, upath
         | _ -> w.root, upath)
    in
    (* A use is the path of a folder from the root: src/shapes. *)
    let dir = Filename.concat root path in
    let files = Package.files dir in
    if files = [] then begin
      let found = Package.folder root path in
      if (not (String.contains path '/')) && Package.files found <> [] then
        use_error ~file:from ~pos ~kind:"name" (Messages.use_path path (Package.shown found));
      missing dir
    end;
    dir, reader w ~from ~pos upath files, false

let native_module w name natives =
  let key = "native:" ^ name in
  match Hashtbl.find_opt w.loaded key with
  | Some m -> m
  | None ->
    let cells = Array.of_list (List.map snd natives) in
    let mnames = List.mapi (fun i (n, _) -> n, i) natives in
    let stable = Array.make (Array.length cells) true in
    let host = Array.length w.modules in
    let m = add_module w { mname = name; path = ""; cells; mnames; stable; host; package = [| host |]; uses = [] } in
    Hashtbl.replace w.loaded key m;
    m

(* The modules written in OCaml: std/sys. *)
let find_native w upath = Option.bind (standard upath) (fun name -> List.assoc_opt name w.native_modules)

(* Does a package of std/ also have a source in Cesia, as std/list does beside its natives: the project's copy or Cesia's own. *)
let has_source w upath =
  match standard upath with
  | Some name -> Package.files (Filename.concat (Filename.concat w.root "std") name) <> [] || own_library name <> None
  | None -> false

(* The packages of std/ that hold what every file saw before 0.4, when they had no use to write. *)
let homes = [ "io"; "result"; "bug"; "list"; "matrix"; "text"; "dict"; "math"; "fn"; "value"; "fiber"; "cesia"; "sys" ]

(* Does a source define this name? Read only for a message, so the cost is paid on an error. *)
let defines path src name =
  match Parser.program ~hooks:false ~file:path ~nesting:max_int (Lexer.tokens ~file:path src) with
  | fn -> List.exists (fun (text, _, _, _) -> String.equal text name) (Resolve.definitions fn)
  | exception Pos.Load_error _ -> false

(* The package of std/ of a name that no file defines: Print is io.Print. *)
let home w name =
  if not (Lexer.is_public name) then None
  else
    List.find_opt
      (fun p ->
         (match List.assoc_opt p w.native_modules with Some ns -> List.mem_assoc name ns | None -> false)
         || (match own_library p with Some (path, src) -> defines path src name | None -> false))
      homes

(* use a/util and use b/util: the name in the code is their last part, so the second one must not vanish in silence. *)
let check_uses path (fn : Ast.func) =
  let seen = Hashtbl.create 8 in
  Array.iter
    (fun (e : Ast.expr) ->
       match e.e with
       | Use { upath; ualias } ->
         (match Hashtbl.find_opt seen ualias with
          | Some (other, at) ->
            use_error ~file:path ~pos:e.pos ~kind:"name" (Messages.use_same ualias other (Pos.line at))
          | None -> Hashtbl.add seen ualias (upath, e.pos))
       | _ -> ())
    fn.body

(* The names that a file reads from each package it uses, by alias, each once: geo.Area, geo.Rect.Square, geo.Point(x, y) in
   a pattern, geo.Rect as a type, in the code of a text too. Its tokens tell, faster than its tree: no variable has the name
   of an alias, the parser refuses it, so an alias that a dot follows, and no dot precedes, is always the package. *)
let used_names (fn : Ast.func) toks =
  let out = Hashtbl.create 16 in
  Array.iter (fun (e : Ast.expr) -> match e.e with Use { ualias; _ } -> Hashtbl.replace out ualias (Hashtbl.create 16) | _ -> ())
    fn.body;
  let rec scan (toks : Lexer.token array) =
    let n = Array.length toks in
    let rec after j = if j < n && (match toks.(j).t with Lexer.NL -> true | _ -> false) then after (j + 1) else j in
    let dot i = i < n && match toks.(i).t with Lexer.DOT -> true | _ -> false in
    for i = 0 to n - 1 do
      match toks.(i).t with
      | Lexer.NAME alias when dot (i + 1) && not (i > 0 && dot (i - 1)) ->
        (match Hashtbl.find_opt out alias with
         | Some names ->
           let j = after (i + 2) in
           if j < n then (match toks.(j).t with Lexer.NAME name -> Hashtbl.replace names name () | _ -> ())
         | None -> ())
      | Lexer.TEXT parts -> List.iter (function Lexer.Code ts -> scan ts | Lexer.Plain _ -> ()) parts
      | _ -> ()
    done
  in
  if Hashtbl.length out > 0 then scan toks;
  fun alias -> Hashtbl.fold (fun name () acc -> name :: acc) (Hashtbl.find out alias) []

(* A package of std/ with natives and a source in Cesia loads its source only for a file that names something of it. *)
let natives_only w upath names =
  match find_native w upath with
  | Some natives when not (List.exists (fun n -> not (List.mem_assoc n natives)) names && has_source w upath) -> Some natives
  | _ -> None

(* Lexes and parses a source. [use] returns the module of each use, given the names the file reads from it. Gives the names of
   the uses, and the first module of each package they name. *)
let parse w ~hooks ~path ~src ~use =
  let file = register_file w path src in
  let toks = Lexer.tokens ~file:path src in
  let fn = Parser.program ~hooks ~file:path ~nesting:w.limits.nesting toks in
  check_uses path fn;
  let names = used_names fn toks in
  let uses =
    List.filter_map
      (fun (e : Ast.expr) ->
         match e.e with
         | Use { upath; ualias } ->
           let m = use ~pos:e.pos ~names:(names ualias) upath in
           Some ((ualias, in_package w m), w.modules.(m).host)
         | _ -> None)
      (Array.to_list fn.body)
  in
  file, fn, List.split uses

(* The methods of a package are looked for by a value, which knows its struct and not the cells. The struct can be in another
   file than its method: they meet at the host. *)
let add_methods w ~host m (layout : Ast.layout) =
  List.iter
    (fun (sname, name, static, k) -> Hashtbl.replace w.methods (host, sname, name) (w.modules.(m).cells.(k), static))
    layout.methods

(* A struct or an interface of a module already loaded, which a type can name. *)
let is_type w = function
  | Ast.Cell { m; k; _ } when m < Array.length w.modules && k < Array.length w.modules.(m).cells ->
    (match w.modules.(m).cells.(k) with
     | Fun { proto; _ } -> Resolve.struct_fields proto.func <> None
     | Native n -> Hashtbl.mem w.interfaces (w.modules.(m).host, n.nname)
     | _ -> false)
  | _ -> false

(* What the name of an interface holds: it is no value, and the interface itself goes to the world. *)
let add_interfaces w ~host m (layout : Ast.layout) =
  let md = w.modules.(m) in
  List.iter
    (fun (k, (i : Ast.iface)) ->
       md.cells.(k) <- Native.nat i.iname 0 max_int (fun ctx _ -> Runtime.fail ctx Type (Messages.interface_call i.iname));
       md.stable.(k) <- true;
       Hashtbl.replace w.interfaces (host, i.iname) i)
    layout.interfaces

(* The types of the fields of the structs of a package, once its modules are there. *)
let set_checks w (prepared : (int * Ast.layout) list) =
  List.iter (fun (m, (layout : Ast.layout)) -> Array.iter (fun (_, f) -> Compile.set_checks w m f) layout.hoisted) prepared

(* Resolves the files of a package, the modules from [first] on. Each one sees what the others define, small names included,
   before any is resolved: a file can call one that comes after it. [old] gives the cells a file already has, for a reload. *)
let resolve_files w ~lookup ~first ~old parsed =
  let is_type = is_type w and home = home w in
  match parsed with
  | [ (path, _, fn, (spaces, _)) ] ->
    [ Resolve.file ~keep:(old 0) ~is_type ~home ~file:path ~m:first ~lookup ~spaces fn ]
  | _ ->
    Resolve.check_package (List.map (fun (path, _, fn, _) -> path, fn) parsed);
    let seen = Hashtbl.create 64 in
    let keep_of i (_, _, fn, _) =
      let cells = Hashtbl.create 32 and names = ref (List.rev (Array.to_list (old i))) in
      Array.iteri (fun k text -> Hashtbl.replace cells text k) (old i);
      List.iter
        (fun (text, _, _, stable) ->
           let k =
             match Hashtbl.find_opt cells text with
             | Some k -> k
             | None ->
               let k = Hashtbl.length cells in
               Hashtbl.replace cells text k;
               names := text :: !names;
               k
           in
           Hashtbl.replace seen text (Ast.Cell { m = first + i; k; stable }))
        (Resolve.definitions fn);
      Array.of_list (List.rev !names)
    in
    let keeps = List.mapi keep_of parsed in
    let look name =
      match Hashtbl.find_opt seen name with
      | Some b -> Some b
      | None -> lookup name
    in
    let peers = List.map (fun (_, _, fn, _) -> fn) parsed in
    List.mapi
      (fun i ((path, _, fn, (spaces, _)), keep) ->
         Resolve.file ~keep ~peers ~is_type ~home ~file:path ~m:(first + i) ~lookup:look ~spaces fn)
      (List.combine parsed keeps)

(* Loads the files of a package as new modules, their uses first, without running them. The examples of a file have it as
   [host]. [natives] is the module of the natives of a package of std/ that has them, which its files see. *)
let rec prepare_files ?(hooks = false) ?host ?natives ctx ~sources ~lookup =
  let w = ctx.w in
  let parsed =
    List.map
      (fun (path, src) ->
         let file, fn, spaces = parse w ~hooks ~path ~src ~use:(use_module ctx ~hooks ~from:path) in
         path, file, fn, spaces)
      sources
  in
  let first = Array.length w.modules in
  let package = Array.append (Array.init (List.length parsed) (fun i -> first + i)) (Option.to_list natives |> Array.of_list) in
  Option.iter (fun n -> w.modules.(n).package <- package) natives;
  let lookup = match natives with Some n -> with_natives w [| n |] | None -> lookup in
  let layouts = resolve_files w ~lookup ~first ~old:(fun _ -> [||]) parsed in
  let host = match host with Some h -> w.modules.(h).host | None -> first in
  let prepared = List.map2
    (fun (path, file, fn, (_, uses)) (layout : Ast.layout) ->
       let m = Array.length w.modules in
       let n = Array.length layout.cell_names in
       let cells = Array.make n Undef and stable = Array.make n false in
       Array.iter
         (fun (k, f) ->
            cells.(k) <- Fun { proto = Compile.new_proto ~file ~m f; env = [||] };
            stable.(k) <- true)
         layout.hoisted;
       let names = List.mapi (fun k n -> n, k) (Array.to_list layout.cell_names) in
       ignore (add_module w { mname = path; path; cells; mnames = names; stable; host; package; uses });
       add_methods w ~host m layout;
       add_interfaces w ~host m layout;
       file, m, fn, layout)
    parsed layouts
  in
  set_checks w (List.map (fun (_, m, _, layout) -> m, layout) prepared);
  prepared

and use_module ctx ~hooks ~from ~pos ~names upath =
  let w = ctx.w in
  match natives_only w upath names with
  | Some natives -> native_module w upath natives
  | None ->
    let natives = find_native w upath in
    let key, read, in_std = locate w ~from ~pos upath in
    match Hashtbl.find_opt w.loaded key with
    | Some m when m >= 0 -> m
    | Some _ -> use_error ~file:from ~pos ~kind:"name" Messages.use_cycle
    (* Don't stop in a library: it isn't the code being debugged, and it keeps its speed. *)
    | None -> run_package ctx ~hooks:(hooks && not in_std) ?natives:(Option.map (native_module w upath) natives) ~key read

(* Runs the statements of a package, file by file, and gives its first module. *)
and run_package ctx ~hooks ?natives ~key read =
  let w = ctx.w in
  Hashtbl.replace w.loaded key (-1);
  match
    let prepared = prepare_files ~hooks ?natives ctx ~sources:(read ()) ~lookup:(lookup w) in
    List.iter (run_prepared ctx) prepared;
    prepared
  with
  | prepared ->
    let _, m, _, _ = List.hd prepared in
    Hashtbl.replace w.loaded key m;
    m
  | exception e ->
    (* Not a cycle: another use must be able to give the real error. *)
    Hashtbl.remove w.loaded key;
    raise e

and run_prepared ctx (file, m, fn, _) = Compile.run_main ctx ~file ~m fn

let folder ctx dir =
  let key = Package.absolute dir in
  match Hashtbl.find_opt ctx.w.loaded key with
  | Some m when m >= 0 -> m
  | _ ->
    let read path =
      let path = Package.shown path in
      path, In_channel.with_open_bin path In_channel.input_all
    in
    run_package ctx ~hooks:ctx.w.hooks ~key (fun () -> List.map read (Package.files key))

let prepare ?hooks ?host ?natives ctx ~path ~src ~lookup =
  List.hd (prepare_files ?hooks ?host ?natives ctx ~sources:[ path, src ] ~lookup)

(* The natives of the package of std/ that a file of std/ belongs to, std/list.ce or src/std/list.ce, as a module. *)
let std_natives w path =
  let name = Filename.remove_extension (Filename.basename path) in
  if Filename.basename (Filename.dirname path) <> "std" || not (Package.is_source path) then None
  else Option.map (native_module w ("std/" ^ name)) (List.assoc_opt name w.native_modules)

let load ctx path =
  let w = ctx.w in
  if Package.is_dir path then ignore (folder ctx path)
  else
    let src = In_channel.with_open_bin path In_channel.input_all in
    run_prepared ctx (prepare ~hooks:w.hooks ctx ~path ~src ~lookup:(lookup w))

let tool_path name = "tools/" ^ name ^ Package.suffix

(* The debugger loads before the program, with no hooks. A name without / or .ce is a tool of Cesia, or else looked up like
   use. *)
let load_debugger ctx name =
  let w = ctx.w in
  let pos = Pos.make 1 1 in
  let is_file = (String.contains name '/' && standard name = None) || Package.is_source name in
  let path, src =
    if List.mem_assoc name Embedded.tools then tool_path name, List.assoc name Embedded.tools
    else if is_file then
      if Sys.file_exists name then name, read_module ~from:name ~pos name name
      else use_error ~file:name ~pos ~kind:"name" (Messages.use_missing name)
    else
      let _, read, _ = locate w ~from:name ~pos name in
      List.hd (read ())
  in
  let ((_, m, _, _) as prepared) = prepare ctx ~path ~src ~lookup:(lookup w) in
  run_prepared ctx prepared;
  match List.assoc_opt "OnStop" w.modules.(m).mnames with
  | Some k ->
    w.debug.on_stop <- w.modules.(m).cells.(k);
    w.on_hook <- Debug.hook
  | None -> use_error ~file:path ~pos ~kind:"name" Messages.no_on_stop

(* The natives of the packages of std/, joined by package: std/list has some of Native, Lists and Columns. *)
let std_packages () =
  let groups =
    Native.packages @ Lists.packages
    @ [ "list", Columns.list; "fiber", Fiber.natives; "cesia", Tooling.natives ~libraries @ Docs.natives;
        "debug", Debug.natives; "json", Json.natives; "regex", Regex.natives (); "columns", Columns.natives ]
  in
  List.fold_left
    (fun acc (name, natives) ->
       match List.assoc_opt name acc with
       | Some before -> List.map (fun (n, l) -> if String.equal n name then n, before @ natives else n, l) acc
       | None -> acc @ [ name, natives ])
    [] groups

let no_args = Array { rows = 1; cols = 0; store = V [||]; a_owned = false; a_tip = true }

(* The arguments of the program, sys.Args. *)
let set_args_value w value =
  let sys = Option.value (List.assoc_opt "sys" w.native_modules) ~default:[] in
  w.native_modules <- ("sys", ("Args", value) :: List.remove_assoc "Args" sys) :: List.remove_assoc "sys" w.native_modules

(* Module 0 holds what only the compiler names; the packages of std/ load at their first use. *)
let init w =
  w.native_modules <- std_packages () @ w.native_modules;
  if not (List.mem_assoc "Args" (Option.value (List.assoc_opt "sys" w.native_modules) ~default:[])) then set_args_value w no_args;
  let cells = Array.of_list (List.map snd Native.core) in
  let names = List.mapi (fun i (n, _) -> n, i) Native.core in
  let stable = Array.make (Array.length cells) true in
  w.modules <- [| { mname = "core"; path = ""; cells; mnames = names; stable; host = 0; package = [| 0 |]; uses = [] } |]

(* A use in a reloaded file: the module must already be there, since we are in the middle of the program. *)
let loaded_module w ~from ~pos ~names upath =
  match natives_only w upath names with
  | Some natives -> native_module w upath natives
  | None ->
    let key, _, _ = locate w ~from ~pos upath in
    match Hashtbl.find_opt w.loaded key with
    | Some m when m >= 0 -> m
    | _ -> use_error ~file:from ~pos ~kind:"name" Messages.reload_use

let module_of w path =
  let found = ref (-1) in
  Array.iteri (fun i md -> if String.equal md.path path then found := i) w.modules;
  !found

(* File-level statements are not rerun: only functions change. A deleted function keeps its cell, for calls already
   compiled. *)
let install w m file (layout : Ast.layout) =
  let md = w.modules.(m) in
  let before = Array.length md.cells in
  let added = Array.length layout.cell_names - before in
  md.cells <- Array.append md.cells (Array.make added Undef);
  md.stable <- Array.append md.stable (Array.make added false);
  md.mnames <- List.mapi (fun k name -> name, k) (Array.to_list layout.cell_names);
  Array.iter
    (fun (k, f) ->
       match md.cells.(k) with
       | Fun { proto; env = [||] } -> Compile.replace proto ~file f
       | _ ->
         md.cells.(k) <- Fun { proto = Compile.new_proto ~file ~m f; env = [||] };
         if k >= before then md.stable.(k) <- true)
    layout.hoisted

(* A function moved to another file of the package: a caller outside it still holds the cell of the old file, so that cell
   takes the new code too. *)
let follow_moved w ~first resolved =
  let now = Hashtbl.create 64 in
  List.iteri
    (fun i ((_, file, _, _), (layout : Ast.layout)) ->
       Array.iter (fun (k, f) -> Hashtbl.replace now layout.cell_names.(k) (first + i, file, f)) layout.hoisted)
    resolved;
  List.iteri
    (fun i _ ->
       let m = first + i in
       let md = w.modules.(m) in
       List.iter
         (fun (name, k) ->
            match Hashtbl.find_opt now name, md.cells.(k) with
            | Some (owner, file, f), Fun { proto; env = [||] } when owner <> m -> Compile.replace proto ~file f
            | _ -> ())
         md.mnames)
    resolved

(* A package reloads as one, since its files see each other. Everything is read, parsed and resolved before touching
   anything: at the slightest failure, the old code stays. *)
let reload w path =
  let m = module_of w path in
  if m < 0 then Ok ()
  else
    let package = w.modules.(m).package in
    let members = List.filter (fun k -> w.modules.(k).path <> "") (Array.to_list package) in
    let first = List.hd members in
    match
      let look = with_natives w package in
      let parsed =
        List.map
          (fun k ->
             let path = w.modules.(k).path in
             let src = In_channel.with_open_bin path In_channel.input_all in
             check_installed w ~from:path ~pos:(Pos.make 1 1) path src;
             let file, fn, spaces = parse w ~hooks:w.hooks ~path ~src ~use:(loaded_module w ~from:path) in
             path, file, fn, spaces)
          members
      in
      let old i = Array.of_list (List.map fst w.modules.(first + i).mnames) in
      List.combine parsed (resolve_files w ~lookup:look ~first ~old parsed)
    with
    | exception Pos.Load_error { file; pos; text; hint; _ } ->
      Error (format_error ~source:(source_of w file) ~path:file ~pos ~text ~hint ~trace:[])
    | exception Sys_error text -> Error (text ^ "\n")
    | resolved ->
      Hashtbl.filter_map_inplace (fun (owner, _, _) entry -> if owner = first then None else Some entry) w.methods;
      Hashtbl.filter_map_inplace (fun (owner, _) entry -> if owner = first then None else Some entry) w.interfaces;
      w.reloads <- w.reloads + 1;
      List.iteri
        (fun i ((_, file, _, (_, uses)), layout) ->
           install w (first + i) file layout;
           w.modules.(first + i).uses <- uses;
           add_methods w ~host:first (first + i) layout;
           add_interfaces w ~host:first (first + i) layout)
        resolved;
      follow_moved w ~first resolved;
      set_checks w (List.mapi (fun i (_, layout) -> first + i, layout) resolved);
      Compile.retire_all w;
      Ok ()

(* The files to watch. Sources embedded in the binary don't change. *)
let watched w =
  let is_embedded path =
    List.exists (fun (name, _) -> String.equal path (tool_path name)) Embedded.tools
    || Sys.getenv_opt "CESIA_STD" = None
       && List.exists (fun (name, _) -> String.equal path ("std/" ^ name ^ Package.suffix)) Embedded.files
  in
  List.filter (fun p -> p <> "" && not (is_embedded p)) (List.map (fun md -> md.path) (Array.to_list w.modules))

let set_args w (args : string list) =
  let items = Array.of_list (List.map (fun a -> Text a) args) in
  set_args_value w (Array { rows = 1; cols = Array.length items; store = V items; a_owned = false; a_tip = true })

(* Runs [body] and prints any Cesia error. Returns the exit code. With [strict], an OCaml stack overflow or a memory
   refusal from the system propagate: the fuzzer wants them, a normal program doesn't. *)
let guarded ?(strict = false) w body =
  let ctx = Runtime.create_ctx w in
  (* The fiber that was running: an error shows its stack. *)
  let current () = Option.value w.sched.current ~default:ctx in
  (* A site keeps the source of its compilation: the file may have changed since. *)
  let report_at fiber ~text ~hint at =
    let site = Dynarray.get w.sites (Runtime.user_site fiber at) in
    let path, src = Dynarray.get w.files site.sfile in
    w.err
      (format_error ~source:(Some src) ~path ~pos:site.spos ~text ~hint ~trace:(Runtime.backtrace fiber at))
  in
  let flushed f =
    Runtime.flush_out w;
    flush stdout;
    f ();
    1
  in
  let limit_reached what at =
    flushed (fun () ->
        let m = Messages.limit what in
        if at < 0 || at >= Dynarray.length w.sites then w.err (m.text ^ "\n")
        else report_at (current ()) ~text:m.text ~hint:m.hint at)
  in
  w.yield <- Fiber.yield;
  w.on_panic <-
    (fun fiber e ->
       match e with
       | Value.Kerr { text; hint; at; _ } ->
         Runtime.flush_out w;
         flush stdout;
         report_at fiber ~text ~hint at
       | _ -> ());
  let code =
    try
      w.sched.current <- Some ctx;
      body ctx
    with
    | Pos.Load_error { file; pos; text; hint; _ } ->
      flushed (fun () ->
          w.err (format_error ~source:(source_of w file) ~path:file ~pos ~text ~hint ~trace:[]))
    | Value.Kerr { text; hint; at; _ } -> flushed (fun () -> report_at (current ()) ~text ~hint at)
    | Value.Quit code ->
      Runtime.flush_out w;
      flush stdout;
      code
    | Value.Limit { what; at } -> limit_reached what at
    | Sys_error text -> flushed (fun () -> w.err ("cesia: " ^ text ^ "\n"))
    (* The OCaml stack or the system said no: that is a limit, not a bug. *)
    | Stack_overflow when not strict -> limit_reached "depth" (current ()).site
    | Out_of_memory when not strict -> limit_reached "memory" (current ()).site
  in
  Runtime.flush_out w;
  flush stdout;
  code

let program ctx path args =
  set_args ctx.w args;
  ctx.w.root <- Package.root_of path;
  (* A cesia.toml that asks for a newer Cesia stops the program before it starts, uses or not. *)
  ignore (Package.sources ctx.w.root);
  Option.iter (load_debugger ctx) ctx.w.debugger;
  load ctx path;
  0

let run ?strict w path args = guarded ?strict w (fun ctx -> program ctx path args)

let run_file ?strict w path args =
  guarded ?strict w (fun ctx ->
      init w;
      program ctx path args)

(* A root that no folder can be, as it holds a zero byte: a tool sees Cesia's own libraries, never a project's copies, which
   may come from another version. *)
let tool_root = "\000tools"

let run_tool w name args =
  guarded w (fun ctx ->
      init w;
      set_args w args;
      w.root <- tool_root;
      let path = tool_path name in
      let pos = Pos.make 1 1 in
      let src =
        match List.assoc_opt name Embedded.tools with
        | Some src -> src
        | None -> use_error ~file:path ~pos ~kind:"name" (Messages.use_missing path)
      in
      let ((_, m, _, _) as prepared) = prepare ctx ~path ~src ~lookup:(lookup w) in
      run_prepared ctx prepared;
      match List.assoc_opt "Main" w.modules.(m).mnames with
      | None -> use_error ~file:path ~pos ~kind:"name" Messages.no_main
      | Some k ->
        ctx.b <- 0;
        ctx.site <- 0;
        (match Compile.call_value ctx ~base:2 w.modules.(m).cells.(k) [||] with
         | Struct { shape = { sname = Some "Err"; _ }; fields = [| e |]; _ } ->
           Runtime.flush_out w;
           flush stdout;
           w.err (Value.text_of ctx e ^ "\n");
           1
         | _ -> 0))
