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
  let main =
    Fun.protect ~finally:(fun () -> Loader.checking := false; Loader.prepared_file := ignore) (fun () ->
        let src = In_channel.with_open_bin path In_channel.input_all in
        Loader.prepare ~key:(Package.absolute path) ctx ~path ~src ~lookup:(Loader.lookup w))
  in
  let module_bytes =
    match Aot.build w (List.rev (main :: !files)) with
    | bytes -> bytes
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
  Out_channel.with_open_bin js_path (fun oc -> Out_channel.output_string oc js)

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
