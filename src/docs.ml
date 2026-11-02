open Types

type entry = { name : string; signature : string; text : string }

let comment_text line =
  let t = String.trim line in
  if String.starts_with ~prefix:"--" t then Some (String.sub t 2 (String.length t - 2)) else None

let is_name_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c >= '\128'

let name_end line from =
  let i = ref from in
  while !i < String.length line && is_name_char line.[!i] do incr i done;
  !i

let is_definition line =
  String.starts_with ~prefix:"defn " line
  || String.starts_with ~prefix:"struct " line
  || (let i = name_end line 0 in i > 0 && i < String.length line && line.[i] = '(')

let native_header line =
  if String.starts_with ~prefix:"--- " line then Some (String.trim (String.sub line 4 (String.length line - 4))) else None

(* A line up to the parenthesis that closes its first one, which may be followed by = and a body. *)
let signature_of line =
  match String.index_opt line '(' with
  | None -> line
  | Some start ->
    let n = String.length line in
    let rec go i depth quoted =
      if i >= n then line
      else
        match line.[i] with
        | '"' -> go (i + 1) depth (not quoted)
        | _ when quoted -> go (i + 1) depth quoted
        | '(' -> go (i + 1) (depth + 1) quoted
        | ')' when depth = 1 -> String.sub line 0 (i + 1)
        | ')' -> go (i + 1) (depth - 1) quoted
        | _ -> go (i + 1) depth quoted
    in
    go start 0 false

let drop_prefix prefix s =
  if String.starts_with ~prefix s then Some (String.sub s (String.length prefix) (String.length s - String.length prefix))
  else None

(* The name in a signature: a module's name comes with its dot. *)
let name_of signature =
  let i = name_end signature 0 in
  if i < String.length signature && signature.[i] = '.' then String.sub signature 0 (name_end signature (i + 1))
  else String.sub signature 0 i

let text_of_block block =
  let unindent t = if String.starts_with ~prefix:" " t then String.sub t 1 (String.length t - 1) else t in
  String.trim (String.concat "\n" (List.rev_map unindent block))

let entries src =
  let out = ref [] and block = ref [] and native = ref None in
  let add signature = out := { name = name_of signature; signature; text = text_of_block !block } :: !out in
  let close_native () =
    Option.iter add !native;
    native := None
  in
  List.iter
    (fun line ->
       match native_header line, comment_text line with
       | Some signature, _ ->
         close_native ();
         block := [];
         native := Some signature
       | None, Some text when String.length line > 0 && line.[0] = '-' -> block := text :: !block
       | _ ->
         close_native ();
         if is_definition line then begin
           let rest =
             match drop_prefix "defn " line, drop_prefix "struct " line with
             | Some r, _ -> signature_of r
             | _, Some r -> String.trim r
             | None, None -> signature_of line
           in
           add rest
         end;
         block := [])
    (String.split_on_char '\n' src);
  close_native ();
  List.rev !out

let public name = String.length name > 0 && name.[0] <> '_'
let shown e = if e.text = "" then e.signature else e.signature ^ "\n\n" ^ e.text
let std name = List.assoc_opt name Embedded.files
let not_modules = [ "prelude"; "natives" ]

(* An editor asks often, so a file of std/ is read once. *)
let read = Hashtbl.create 32

let std_entries name =
  match Hashtbl.find_opt read name with
  | Some es -> es
  | None ->
    let es = entries (Option.value (std name) ~default:"") in
    Hashtbl.add read name es;
    es

let natives_entries () = std_entries "natives"

let find name es = List.find_opt (fun e -> String.equal e.name name) es

(* A comment at the top of a file says what the module is for. *)
let module_text src =
  let rec go acc = function
    | line :: rest when String.starts_with ~prefix:"--" line -> go (Option.get (comment_text line) :: acc) rest
    | _ -> text_of_block acc
  in
  go [] (String.split_on_char '\n' src)

let lookup name =
  let native = find name (natives_entries ()) in
  let entry =
    match String.index_opt name '.' with
    | None -> (match find name (std_entries "prelude") with Some e -> Some e | None -> native)
    | Some i ->
      let m = String.sub name 0 i and short = String.sub name (i + 1) (String.length name - i - 1) in
      (match if public short then find short (std_entries m) else None with
       | Some e -> Some e
       | None -> native)
  in
  if public name then Option.map shown entry else None

let modules w =
  let embedded = List.filter (fun m -> not (List.mem m not_modules)) (List.map fst Embedded.files) in
  "prelude" :: List.sort_uniq String.compare (embedded @ List.map fst w.native_modules)

let is_module w m = List.mem m (modules w)

let short_name n = match String.rindex_opt n '.' with Some i -> String.sub n (i + 1) (String.length n - i - 1) | None -> n

let names w m =
  let qualified n = if m = "prelude" then n else m ^ "." ^ n in
  let native_names =
    if m = "prelude" then
      List.map fst w.modules.(0).mnames
      @ List.filter_map (fun e -> if String.contains e.name '.' then None else Some e.name) (natives_entries ())
    else
      List.map (fun (n, _) -> m ^ "." ^ n) (Option.value (List.assoc_opt m w.native_modules) ~default:[])
      @ List.filter_map (fun e -> Option.map (fun _ -> e.name) (drop_prefix (m ^ ".") e.name)) (natives_entries ())
  in
  let written = List.map (fun e -> qualified e.name) (std_entries m) in
  List.sort_uniq String.compare (List.filter (fun n -> public (short_name n)) (native_names @ written))

(* What a function value was defined as. A native knows only its short name. *)
let of_function w v =
  match v with
  | Fun { proto; _ } ->
    let _, src = Dynarray.get w.files proto.file in
    if public proto.pname then Option.map shown (find proto.pname (entries src)) else None
  | Native n ->
    (match lookup n.nname with
     | Some text -> Some text
     | None ->
       let suffix = "." ^ n.nname in
       Option.map shown (List.find_opt (fun e -> String.ends_with ~suffix e.name) (natives_entries ())))
  | _ -> None

let doc ctx (a : t array) =
  let found =
    match a.(0) with
    | Text name ->
      (match lookup name with
       | Some text -> Some text
       | None when is_module ctx.w name -> Option.map module_text (std name)
       | None -> None)
    | v -> of_function ctx.w v
  in
  match found with Some text -> Text text | None -> Missing

let doc_names ctx (a : t array) =
  let found =
    match a with
    | [||] -> modules ctx.w
    | _ ->
      let m = Native.text_arg ctx "doc_names" a.(0) in
      if is_module ctx.w m then names ctx.w m else []
  in
  Arrays.list (Array.of_list (List.map (fun s -> Text s) found))

let natives =
  [ "doc", Native.nat "doc" 1 1 doc;
    "doc_names", Native.nat "doc_names" 0 1 doc_names ]

let first_line text = match String.index_opt text '\n' with Some i -> String.sub text 0 i | None -> text

(* The sentence after the signature of a name. *)
let summary name =
  match lookup name with
  | None -> ""
  | Some text ->
    (match String.index_opt text '\n' with
     | Some i -> first_line (String.trim (String.sub text i (String.length text - i)))
     | None -> "")

let command w args =
  let table rows =
    let width = List.fold_left (fun n (a, _) -> max n (String.length a)) 0 rows in
    List.iter (fun (a, b) -> print_endline (String.trim (Printf.sprintf "%-*s  %s" width a b))) rows
  in
  match args with
  | [] ->
    table (List.map (fun m -> m, first_line (module_text (Option.value (std m) ~default:""))) (modules w));
    0
  | [ name ] when is_module w name ->
    let head = module_text (Option.value (std name) ~default:"") in
    if head <> "" && name <> "prelude" then print_endline (head ^ "\n");
    table (List.map (fun n -> n, summary n) (names w name));
    0
  | [ name ] ->
    (match lookup name with
     | Some text ->
       print_endline text;
       0
     | None ->
       prerr_endline (Messages.doc_missing name);
       1)
  | _ ->
    prerr_endline Messages.usage;
    2
