(* Generates src/bin/build.ml: a digest of the files given, the sources of Cesia's core and the OCaml that builds it, which
   names this build in the cache of loaded packages: another build never reads what this one saved. *)

let () =
  let read p = if Sys.file_exists p then Filename.basename p ^ "\000" ^ In_channel.with_open_bin p In_channel.input_all else p in
  let text = String.concat "\000" (List.map read (List.tl (Array.to_list Sys.argv))) in
  Printf.printf "let id = %S\n" (Digest.BLAKE128.to_hex (Digest.BLAKE128.string text))
