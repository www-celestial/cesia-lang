open Types

let fingerprint = Package.fingerprint
let texts items = Arrays.list (Array.of_list (List.map (fun s -> Text s) items))
let record (_ : world) names fields = Trie.record (Trie.names names) fields
let records w names rows = Arrays.list (Array.of_list (List.map (record w names) rows))
let refused w line message = Value.err w (record w [| "Line"; "Message" |] [| Int line; Text message |])

let value = function
  | Toml.Text s -> Text s
  | Texts l -> texts l
  | Flag b -> Value.of_bool b

let toml ctx a =
  let w = ctx.w in
  match Toml.parse (Native.text_arg ctx "cesia.Toml" a.(0)) with
  | Error (line, reason) -> refused w line reason
  | Ok tables ->
    let entry (e : Toml.entry) = [| Text e.key; value e.value; Int e.line |] in
    let table (t : Toml.table) =
      [| texts t.path; Int t.start; records w [| "Key"; "Value"; "Line" |] (List.map entry t.entries) |]
    in
    Value.ok w (records w [| "Path"; "Line"; "Entries" |] (List.map table tables))

(* The paths of the uses of a source, as the loader reads them: nothing of it runs. *)
let uses ctx a =
  let w = ctx.w in
  let src = Native.text_arg ctx "cesia.Uses" a.(0) in
  match Parser.program ~file:"" ~nesting:w.limits.nesting (Lexer.tokens ~file:"" src) with
  | fn ->
    let path (e : Ast.expr) = match e.e with Use { upath; _ } -> Some upath | _ -> None in
    Value.ok w (texts (List.filter_map path (Array.to_list fn.body)))
  | exception Pos.Load_error { pos; text; _ } -> refused w (Pos.line pos) text

(* The tree of a source with every position the same, so that two sources that differ only by their spaces, line ends and
   comments give equal trees: what cesia fmt checks before it writes a file. *)
let tree w src =
  let rec flat (tk : Lexer.token) =
    let t = match tk.t with TEXT parts -> Lexer.TEXT (List.map (function Lexer.Code c -> Lexer.Code (Array.map flat c) | p -> p) parts) | t -> t in
    { tk with t; pos = Pos.make 1 1 }
  in
  let toks = Lexer.tokens ~file:"" src in
  (* A source that doesn't read says where, while its tokens still have their places. *)
  ignore (Parser.program ~file:"" ~nesting:w.limits.nesting toks);
  Parser.program ~file:"" ~nesting:w.limits.nesting (Array.map flat toks)

let same_tree ctx a =
  let w = ctx.w in
  let src k = Native.text_arg ctx "cesia.SameTree" a.(k) in
  match tree w (src 0) = tree w (src 1) with
  | same -> Value.ok w (Value.of_bool same)
  | exception Pos.Load_error { pos; text; _ } -> refused w (Pos.line pos) text

let natives ~libraries =
  let text name f = name, Native.nat ("cesia." ^ name) 1 1 (fun ctx a -> f ctx (Native.text_arg ctx ("cesia." ^ name) a.(0))) in
  [ "Version", Native.nat "cesia.Version" 0 0 (fun _ _ -> Text Version.number);
    "IsDev", Native.nat "cesia.IsDev" 0 0 (fun _ _ -> Value.of_bool Version.dev);
    "Binary", Native.nat "cesia.Binary" 0 0 (fun _ _ -> Text Sys.executable_name);
    text "Fingerprint" (fun _ src -> Text (fingerprint src));
    "Compare",
    Native.nat "cesia.Compare" 2 2 (fun ctx a ->
        Int (Version.compare (Native.text_arg ctx "cesia.Compare" a.(0)) (Native.text_arg ctx "cesia.Compare" a.(1))));
    text "IsVersion" (fun _ v -> Value.of_bool (Version.valid v));
    "Libraries",
    Native.nat "cesia.Libraries" 0 0 (fun ctx _ ->
        records ctx.w [| "Name"; "Source" |] (List.map (fun (name, src) -> [| Text name; Text src |]) (libraries ())));
    "Toml", Native.nat ~result:true "cesia.Toml" 1 1 toml;
    "DocEntry", Native.nat "cesia.DocEntry" 1 1 Docs.doc_entry;
    "Definitions", Native.nat ~result:true "cesia.Definitions" 1 1 Docs.definitions;
    "Keywords", Native.nat "cesia.Keywords" 0 0 (fun _ _ -> texts Lexer.words);
    text "Asset" (fun _ name -> match List.assoc_opt name Embedded.assets with Some s -> Text s | None -> Missing);
    "Uses", Native.nat ~result:true "cesia.Uses" 1 1 uses;
    "SameTree", Native.nat ~result:true "cesia.SameTree" 2 2 same_tree ]
