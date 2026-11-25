(* The plugin's entry: loaded by the binary for cesia build, which gives it its arguments. *)

let stop text = prerr_endline ("cesia: " ^ text); exit 2

(* Loads a program as cesia run does, but runs none of it: each file of the packages it uses is seen as it would run,
   then the file itself. *)
let build (ctx : Types.ctx) path =
  let w = ctx.w in
  w.root <- Package.root_of path;
  ignore (Package.sources w.root);
  w.debug.main <- path;
  let files = ref [] in
  Loader.checking := true;
  Loader.prepared_file := (fun p -> files := p :: !files);
  let main, pages =
    Fun.protect ~finally:(fun () -> Loader.checking := false; Loader.prepared_file := ignore) (fun () ->
        let src = In_channel.with_open_bin path In_channel.input_all in
        let main = Loader.prepare ~key:(Package.absolute path) ctx ~path ~src ~lookup:(Loader.lookup w) in
        (* The packages that a page has a version of, in src/web/, once the program uses them: their functions and
           natives of the same names are taken (Aot.call_expr). A version may use another package that has one. *)
        let used pkg = Array.exists (fun (md : Types.modul) -> md.mname = pkg || md.path = pkg ^ ".ce") w.modules in
        let rec more pages =
          match List.find_opt (fun (pkg, _) -> used pkg && not (List.mem_assoc pkg pages)) Pages.all with
          | Some (pkg, src) ->
            let ((_, m, _, _) as p) =
              Loader.prepare ~key:("page:" ^ pkg) ctx ~path:("std/page/" ^ Filename.basename pkg ^ ".ce") ~src ~lookup:(Loader.lookup w)
            in
            files := p :: !files;
            more ((pkg, m) :: pages)
          | None -> pages
        in
        main, more [])
  in
  let module_bytes, scripts =
    match Aot.build ~pages w (List.rev (main :: !files)) with
    | built -> built
    | exception Aot.Unsupported (file, pos, what) ->
      let m = Messages.wasm_unsupported what in
      raise (Pos.Load_error { file; pos; kind = "build"; text = m.text; hint = m.hint })
  in
  let base = Filename.remove_extension path in
  let name = Filename.basename base in
  (* The loader as a page fetches it: its first line, which tells it from another .js, then its code without the
     comments and indents of src/web/glue.js. *)
  let glue =
    match String.split_on_char '\n' Glue.text with
    | first :: rest ->
      String.concat "\n"
        (first :: List.filter_map (fun l -> let l = String.trim l in if l = "" || String.starts_with ~prefix:"//" l then None else Some l) rest)
      ^ "\n"
    | [] -> Glue.text
  in
  (* A .js of that name that this build didn't write stays: it may be the program's own. *)
  let first s = match String.index_opt s '\n' with Some i -> String.sub s 0 i | None -> s in
  let js_path = base ^ ".js" in
  if Sys.file_exists js_path && first (In_channel.with_open_bin js_path In_channel.input_all) <> first glue then begin
    stop (Messages.wasm_overwrite js_path)
  end;
  Out_channel.with_open_bin (base ^ ".wasm") (fun oc -> Out_channel.output_string oc module_bytes);
  let rec find i = if String.sub glue i 6 = "@WASM@" then i else find (i + 1) in
  let at = find 0 in
  let js = String.sub glue 0 at ^ name ^ ".wasm" ^ String.sub glue (at + 6) (String.length glue - at - 6) in
  Out_channel.with_open_bin js_path (fun oc -> Out_channel.output_string oc js);
  (* The JavaScript modules that js.Call names, beside the program, where its loader imports them. *)
  List.iter
    (fun (file, base) ->
       let src = try In_channel.with_open_bin file In_channel.input_all with Sys_error _ -> stop (Messages.cant_read file) in
       let dest = Filename.concat (Filename.dirname path) base in
       if not (Sys.file_exists dest && Package.absolute dest = Package.absolute file) then
         Out_channel.with_open_bin dest (fun oc -> Out_channel.output_string oc src))
    scripts

(* cesia build --target wasm file.ce: file.wasm and its loader file.js beside it; the exit code. *)
let main = function
  | [ "--target"; "wasm"; file ] ->
    if not (Sys.file_exists file) then stop (Messages.cant_read file);
    let o = Runtime.default_options in
    let w = Runtime.create_world { o with o_limits = { o.o_limits with memory_words = Runtime.default_memory (Cesia_sys.Sys_modules.ram ()) } } in
    let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
    Loader.guarded w (fun ctx -> Loader.init w; build ctx file; 0)
  | _ -> prerr_endline Messages.usage; 2

let () = Loader.builder := Some main
