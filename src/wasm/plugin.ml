(* The plugin's entry: loaded by the binary for cesia build, it gives the binary the compiler. *)

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
  Out_channel.with_open_bin (base ^ ".wasm") (fun oc -> Out_channel.output_string oc module_bytes);
  let glue = Glue.text in
  let rec find i = if String.sub glue i 6 = "@WASM@" then i else find (i + 1) in
  let at = find 0 in
  let js = String.sub glue 0 at ^ name ^ ".wasm" ^ String.sub glue (at + 6) (String.length glue - at - 6) in
  Out_channel.with_open_bin (base ^ ".js") (fun oc -> Out_channel.output_string oc js)

let () = Loader.builder := Some build
