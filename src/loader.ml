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

(* The prelude: module 1 written in Kepler, then module 0 of natives. A name starting with _ stays private. *)
let lookup w name =
  if String.starts_with ~prefix:"_" name then None
  else
    match in_module w 1 name with
    | Some b -> Some b
    | None -> in_module w 0 name

let message_of_error = function
  | Pos.Load_error { text; _ } -> Some text
  | Value.Kerr { text; _ } -> Some text
  | Value.Limit { what; _ } -> Some (Messages.limit what).text
  | Stack_overflow -> Some (Messages.limit "depth").text
  | Out_of_memory -> Some (Messages.limit "memory").text
  | _ -> None

let std_source name =
  match Sys.getenv_opt "KEPLER_STD" with
  | Some dir ->
    let path = Filename.concat dir (name ^ ".kp") in
    if Sys.file_exists path then Some (path, In_channel.with_open_bin path In_channel.input_all) else None
  | None ->
    Option.map (fun src -> "std/" ^ name ^ ".kp", src) (List.assoc_opt name Embedded.files)

let use_error ~file ~pos ~kind (m : Messages.t) =
  raise (Pos.Load_error { file; pos; kind; text = m.text; hint = m.hint })

let read_module ~from ~pos upath path =
  try In_channel.with_open_bin path In_channel.input_all
  with Sys_error _ -> use_error ~file:from ~pos ~kind:"name" (Messages.use_unreadable upath)

(* The file of a use, without loading it. *)
let locate w ~from ~pos upath is_name =
  if is_name then
    match std_source upath with
    | Some s -> s
    | None -> use_error ~file:from ~pos ~kind:"name" (Messages.use_missing upath)
  else begin
    let path = Runtime.normalize (Filename.concat (Filename.dirname from) upath ^ ".kp") in
    if (not (Runtime.granted w Read (Some path))) && not (Runtime.inside w.entry_dir path) then
      use_error ~file:from ~pos ~kind:"permission" (Messages.denied "read");
    if not (Sys.file_exists path) then use_error ~file:from ~pos ~kind:"name" (Messages.use_missing upath);
    path, read_module ~from ~pos upath path
  end

let native_module w name natives =
  let key = "native:" ^ name in
  match Hashtbl.find_opt w.loaded key with
  | Some m -> m
  | None ->
    let cells = Array.of_list (List.map snd natives) in
    let mnames = List.mapi (fun i (n, _) -> n, i) natives in
    let stable = Array.make (Array.length cells) true in
    let m = add_module w { mname = name; path = ""; cells; mnames; stable } in
    Hashtbl.replace w.loaded key m;
    m

(* The modules written in OCaml, which use finds before std/. *)
let find_native w upath is_name = if is_name then List.assoc_opt upath w.native_modules else None

(* Lexes and parses a source. [use] returns the module of each use. *)
let parse w ~hooks ~path ~src ~use =
  let file = register_file w path src in
  let toks = Lexer.tokens ~file:path src in
  let fn = Parser.program ~hooks ~file:path ~nesting:w.limits.nesting toks in
  let spaces =
    List.filter_map
      (fun (e : Ast.expr) ->
         match e.e with
         | Use { upath; is_name; ualias } -> Some (ualias, in_module w (use ~pos:e.pos upath is_name))
         | _ -> None)
      (Array.to_list fn.body)
  in
  file, fn, spaces

(* Loads a source as a new module, its uses first, without running it. *)
let rec prepare ?(hooks = false) ctx ~path ~src ~lookup =
  let w = ctx.w in
  let file, fn, spaces = parse w ~hooks ~path ~src ~use:(use_module ctx ~hooks ~from:path) in
  let m = Array.length w.modules in
  let layout = Resolve.file ~file:path ~m ~lookup ~spaces fn in
  let n = Array.length layout.cell_names in
  let cells = Array.make n Undef and stable = Array.make n false in
  Array.iter
    (fun (k, f) ->
       cells.(k) <- Fun { proto = Compile.new_proto ~file ~m f; env = [||] };
       stable.(k) <- true)
    layout.hoisted;
  let names = List.mapi (fun k n -> n, k) (Array.to_list layout.cell_names) in
  ignore (add_module w { mname = path; path; cells; mnames = names; stable });
  file, m, fn, layout

and use_module ctx ~hooks ~from ~pos upath is_name =
  let w = ctx.w in
  match find_native w upath is_name with
  | Some natives -> native_module w upath natives
  | None ->
    let path, src = locate w ~from ~pos upath is_name in
    match Hashtbl.find_opt w.loaded path with
    | Some m when m >= 0 -> m
    | Some _ -> use_error ~file:from ~pos ~kind:"name" Messages.use_cycle
    | None ->
      Hashtbl.replace w.loaded path (-1);
      (* Don't stop in std/: it isn't the code being debugged. *)
      match
        let prepared = prepare ~hooks:(hooks && not is_name) ctx ~path ~src ~lookup:(lookup w) in
        run_prepared ctx prepared;
        prepared
      with
      | _, m, _, _ ->
        Hashtbl.replace w.loaded path m;
        m
      | exception e ->
        (* Not a cycle: another use must be able to give the real error. *)
        Hashtbl.remove w.loaded path;
        raise e

and run_prepared ctx (file, m, fn, _) = Compile.run_main ctx ~file ~m fn

let load ctx path =
  let w = ctx.w in
  let src = In_channel.with_open_bin path In_channel.input_all in
  w.entry_dir <- Filename.dirname path;
  let prepared = prepare ~hooks:w.hooks ctx ~path ~src ~lookup:(lookup w) in
  run_prepared ctx prepared;
  prepared

(* The debugger loads before the program, with no hooks. A name without / or .kp is looked up like use. *)
let load_debugger ctx name =
  let w = ctx.w in
  let pos = Pos.make 1 1 in
  let is_file = String.contains name '/' || Filename.check_suffix name ".kp" in
  let path, src =
    if is_file then
      if Sys.file_exists name then name, read_module ~from:name ~pos name name
      else use_error ~file:name ~pos ~kind:"name" (Messages.use_missing name)
    else locate w ~from:name ~pos name true
  in
  if is_file then w.entry_dir <- Filename.dirname path;
  let ((_, m, _, _) as prepared) = prepare ctx ~path ~src ~lookup:(lookup w) in
  run_prepared ctx prepared;
  match List.assoc_opt "on_stop" w.modules.(m).mnames with
  | Some k ->
    w.debug.on_stop <- w.modules.(m).cells.(k);
    w.on_hook <- Debug.hook
  | None -> use_error ~file:path ~pos ~kind:"name" Messages.no_on_stop

(* Module 0 of natives, then the prelude in Kepler. *)
let init w =
  w.native_modules <- ("debug", Debug.natives) :: ("json", Json.natives) :: ("regex", Regex.natives ()) :: ("columns", Columns.natives) :: w.native_modules;
  let natives = Native.prelude @ Lists.natives @ Fiber.natives @ Docs.natives in
  let names = List.mapi (fun i (n, _) -> n, i) natives in
  let cells = Array.of_list (List.map snd natives) in
  let stable = Array.make (Array.length cells) true in
  w.modules <- [| { mname = "natives"; path = ""; cells; mnames = names; stable } |];
  let ctx = Runtime.create_ctx w in
  match std_source "prelude" with
  | Some (path, src) ->
    let natives name = in_module w 0 name in
    run_prepared ctx (prepare ctx ~path ~src ~lookup:natives)
  | None ->
    let dir = Option.value (Sys.getenv_opt "KEPLER_STD") ~default:"std" in
    use_error ~file:dir ~pos:(Pos.make 1 1) ~kind:"name" Messages.no_prelude

(* A use in a reloaded file: the module must already be there, since we are in the middle of the program. *)
let loaded_module w ~from ~pos upath is_name =
  match find_native w upath is_name with
  | Some natives -> native_module w upath natives
  | None ->
    let path, _ = locate w ~from ~pos upath is_name in
    match Hashtbl.find_opt w.loaded path with
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
    layout.hoisted;
  Compile.retire_all w

(* Everything is read, parsed and resolved before touching anything: at the slightest failure, the old code stays. *)
let reload w path =
  let m = module_of w path in
  if m < 0 then Ok ()
  else
    match
      let src = In_channel.with_open_bin path In_channel.input_all in
      let file, fn, spaces = parse w ~hooks:w.hooks ~path ~src ~use:(loaded_module w ~from:path) in
      let keep = Array.of_list (List.map fst w.modules.(m).mnames) in
      let look = if m = 1 then in_module w 0 else lookup w in
      file, Resolve.file ~keep ~file:path ~m ~lookup:look ~spaces fn
    with
    | exception Pos.Load_error { file; pos; text; hint; _ } ->
      Error (format_error ~source:(source_of w file) ~path:file ~pos ~text ~hint ~trace:[])
    | exception Sys_error text -> Error (text ^ "\n")
    | file, layout ->
      install w m file layout;
      Ok ()

(* The files to watch. Sources embedded in the binary don't change. *)
let watched w =
  let is_embedded path =
    Sys.getenv_opt "KEPLER_STD" = None
    && List.exists (fun (name, _) -> String.equal path ("std/" ^ name ^ ".kp")) Embedded.files
  in
  List.filter (fun p -> p <> "" && not (is_embedded p)) (List.map (fun md -> md.path) (Array.to_list w.modules))

let set_args w (args : string list) =
  match List.assoc_opt "args" w.modules.(0).mnames with
  | Some k ->
    let items = Array.of_list (List.map (fun a -> Text a) args) in
    w.modules.(0).cells.(k) <- Array { rows = 1; cols = Array.length items; store = V items; a_owned = false }
  | None -> ()

(* Runs [body] and prints any Kepler error. Returns the exit code. With [strict], an OCaml stack overflow or a memory
   refusal from the system propagate: the fuzzer wants them, a normal program doesn't. *)
let guarded ?(strict = false) w body =
  let ctx = Runtime.create_ctx w in
  (* The fiber that was running: an error shows its stack. *)
  let current () = Option.value w.sched.current ~default:ctx in
  (* A site keeps the source of its compilation: the file may have changed since. *)
  let report_at fiber ~text ~hint at =
    let site = Dynarray.get w.sites at in
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
    | Value.Limit { what; at } -> limit_reached what at
    | Sys_error text -> flushed (fun () -> w.err ("kepler: " ^ text ^ "\n"))
    (* The OCaml stack or the system said no: that is a limit, not a bug. *)
    | Stack_overflow when not strict -> limit_reached "depth" (current ()).site
    | Out_of_memory when not strict -> limit_reached "memory" (current ()).site
  in
  Runtime.flush_out w;
  flush stdout;
  code

let program ctx path args =
  set_args ctx.w args;
  Option.iter (load_debugger ctx) ctx.w.debugger;
  ignore (load ctx path);
  0

let run ?strict w path args = guarded ?strict w (fun ctx -> program ctx path args)

let run_file ?strict w path args =
  guarded ?strict w (fun ctx ->
      init w;
      program ctx path args)
