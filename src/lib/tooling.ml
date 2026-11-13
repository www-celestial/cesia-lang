open Types

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
    Value.ok w (texts (List.filter_map path (Array.to_list (Lazy.force fn.body))))
  | exception Pos.Load_error { pos; text; _ } -> refused w (Pos.line pos) text

(* The names a source reads and doesn't define, as the resolver finds them: each once, at its first place. The source is
   resolved as a file alone, with a lookup that takes every name it is asked for, which marks it free. Its own uses are
   packages, and so is a name before a dot that nothing defines, as io in io.Print: the source reads that name. *)
let reads ctx a =
  let w = ctx.w in
  let src = Native.text_arg ctx "cesia.Reads" a.(0) in
  match
    let toks = Lexer.tokens ~file:"" src in
    toks, Parser.program ~file:"" ~nesting:w.limits.nesting toks
  with
  | exception Pos.Load_error { pos; text; _ } -> refused w (Pos.line pos) text
  | toks, fn ->
    let free = Ast.Cell { m = -1; k = 0; stable = false } in
    let first = Hashtbl.create 16 in
    let note name pos =
      match Hashtbl.find_opt first name with
      | Some p when p <= pos -> ()
      | _ -> Hashtbl.replace first name pos
    in
    let named = Hashtbl.create 64 and dotted = Hashtbl.create 16 in
    let rec scan (toks : Lexer.token array) =
      let n = Array.length toks in
      let dot i = i >= 0 && i < n && toks.(i).t = DOT in
      Array.iteri
        (fun i (tk : Lexer.token) ->
           match tk.t with
           | NAME s ->
             if not (Hashtbl.mem named s) then Hashtbl.add named s tk.pos;
             if dot (i + 1) && (not (dot (i - 1))) && not (Hashtbl.mem dotted s) then Hashtbl.add dotted s tk.pos
           | TEXT parts -> List.iter (function Lexer.Code c -> scan c | Plain _ -> ()) parts
           | _ -> ())
        toks
    in
    scan toks;
    let own = List.filter_map (fun (e : Ast.expr) -> match e.e with Use { ualias; _ } -> Some ualias | _ -> None) (Array.to_list (Lazy.force fn.body)) in
    let looked = Hashtbl.create 16 in
    let lookup name =
      if name = "" || name.[0] = '#' || String.contains name '.' || String.contains name ':' then None
      else begin
        Hashtbl.replace looked name ();
        Some free
      end
    in
    let space alias = if List.mem alias own then fun _ -> Some Ast.Unresolved else fun _ -> note alias (Hashtbl.find dotted alias); Some Ast.Unresolved in
    let spaces = Hashtbl.fold (fun alias _ acc -> (alias, space alias) :: acc) dotted [] in
    ignore (Resolve.file ~report:ignore ~file:"" ~m:(-1) ~lookup ~spaces fn);
    let rec walk (e : Ast.expr) =
      (match e.e with
       | Var { text; b } when b = free -> note text e.pos
       (* x.hidden, where x is no package: the resolver leaves it, as a private name of a package is an error. *)
       | Var { text; b = Unresolved } when Hashtbl.mem dotted text && not (List.mem text own) -> note text e.pos
       | Lambda f | Fn_def (_, f) -> body f
       | _ -> ());
      Resolve.children walk e
    and body (f : Ast.func) =
      Array.iter (fun (p : Ast.param) -> Option.iter walk p.default) f.params;
      Array.iter walk (Lazy.force f.body)
    in
    body fn;
    (* A struct or an interface named by a pattern or a type is no variable: its first place is that of its name. *)
    let own_names = List.map (fun (text, _, _, _) -> text) (Resolve.definitions fn) in
    Hashtbl.iter
      (fun name () ->
         if not (Hashtbl.mem first name || List.mem name own_names) then Option.iter (note name) (Hashtbl.find_opt named name))
      looked;
    let found = List.sort (fun (_, p) (_, q) -> compare p q) (Hashtbl.fold (fun name pos acc -> (name, pos) :: acc) first []) in
    let row (name, pos) = [| Text name; Int (Pos.line pos); Int (Pos.col pos) |] in
    Value.ok w (records w [| "Name"; "Line"; "Column" |] (List.map row found))

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
    text "Fingerprint" (fun _ src -> Text (Package.fingerprint src));
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
    "Reads", Native.nat ~result:true "cesia.Reads" 1 1 reads;
    "SameTree", Native.nat ~result:true "cesia.SameTree" 2 2 same_tree ]
