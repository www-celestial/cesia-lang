open Types

type entry = { name : string; signature : string; text : string }

let comment_text line =
  let t = String.trim line in
  if String.starts_with ~prefix:"--" t then Some (String.sub t 2 (String.length t - 2)) else None

(* How deep in comments a line ends, starting at this depth. A text or a -- in code hides what follows it. *)
let depth_after depth line =
  let n = String.length line in
  let rec go i d in_text =
    if i >= n then d
    else if in_text then go (i + 1) d (line.[i] <> '"')
    else if i + 1 < n && line.[i] = '(' && line.[i + 1] = '*' then go (i + 2) (d + 1) false
    else if d > 0 && i + 1 < n && line.[i] = '*' && line.[i + 1] = ')' then go (i + 2) (d - 1) false
    else if d = 0 && line.[i] = '"' then go (i + 1) d true
    else if d = 0 && i + 1 < n && line.[i] = '-' && line.[i + 1] = '-' then d
    else go (i + 1) d false
  in
  go 0 depth false

(* The words of one line of a documentation comment, as the line after -- would give them. *)
let block_text ~first line =
  let t = if first then String.sub line 3 (String.length line - 3) else line in
  let t = String.trim (if String.ends_with ~suffix:"**)" t then String.sub t 0 (String.length t - 3) else if String.ends_with ~suffix:"*)" t then String.sub t 0 (String.length t - 2) else t) in
  let n = String.length line in
  let rec spaces i = if i < n && line.[i] = ' ' then spaces (i + 1) else i in
  let extra = if first then 0 else max 0 (spaces 0 - 4) in
  "-- " ^ String.make extra ' ' ^ t

(* The lines of a source with its comment blocks read: a (** ... *) at the start of a line becomes -- lines, and any other block
   empty lines, so that its contents aren't taken for definitions. Lines keep their numbers. *)
let lines src =
  let depth = ref 0 and doc = ref false in
  List.map
    (fun line ->
       let before = !depth in
       depth := depth_after before line;
       if before > 0 then (if !doc then block_text ~first:false line else "")
       else if String.starts_with ~prefix:"(*" line then begin
         doc := String.starts_with ~prefix:"(**" line && String.length line > 4;
         if !doc then block_text ~first:true line else ""
       end
       else begin
         doc := false;
         line
       end)
    (String.split_on_char '\n' src)

let is_name_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c >= '\128'

let name_end line from =
  let i = ref from in
  while !i < String.length line && is_name_char line.[!i] do incr i done;
  !i

let native_header line =
  if String.starts_with ~prefix:"--- " line then Some (String.trim (String.sub line 4 (String.length line - 4))) else None

(* Where the space after the (r Rect) of a line is, when the line starts with one. *)
let receiver_end line =
  let n = String.length line in
  if n = 0 || line.[0] <> '(' then None
  else
    let self = name_end line 1 in
    if self = 1 || self >= n || line.[self] <> ' ' then None
    else
      let sname = name_end line (self + 1) in
      if sname > self + 1 && sname + 1 < n && line.[sname] = ')' && line.[sname + 1] = ' ' then Some (sname + 1) else None

(* A line up to the parenthesis that closes its first one, after an object if it has one, which may be followed by = and a
   body. *)
let signature_of line =
  match String.index_from_opt line (Option.value (receiver_end line) ~default:0) '(' with
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

(* (r Rect) IsEmpty() = ... or Rect.Unit() = ..., and not a call of a module at the start of a line: the name is after [i]. *)
let is_short_method line i =
  let from = i + 1 in
  let upto = name_end line from in
  upto > from && upto < String.length line && line.[upto] = '('
  &&
  let n = String.length (signature_of line) in
  let rest = String.trim (String.sub line n (String.length line - n)) in
  String.starts_with ~prefix:"=" rest && not (String.starts_with ~prefix:"==" rest)

let is_definition line =
  String.starts_with ~prefix:"defn " line
  || String.starts_with ~prefix:"struct " line
  || String.starts_with ~prefix:"interface " line
  ||
  match receiver_end line with
  | Some i -> is_short_method line i
  | None ->
    let i = name_end line 0 in
    i > 0 && i < String.length line && (line.[i] = '(' || (line.[i] = '.' && is_short_method line i))

let drop_prefix prefix s =
  if String.starts_with ~prefix s then Some (String.sub s (String.length prefix) (String.length s - String.length prefix))
  else None

(* The name in a signature: a module's name comes with its dot, and a method's with its struct, static or not. *)
let name_of signature =
  match receiver_end signature with
  | Some i ->
    let sname = String.index signature ' ' + 1 in
    String.sub signature sname (i - 1 - sname) ^ "." ^ String.sub signature (i + 1) (name_end signature (i + 1) - i - 1)
  | None ->
    let i = name_end signature 0 in
    if i < String.length signature && signature.[i] = '.' then String.sub signature 0 (name_end signature (i + 1))
    else String.sub signature 0 i

let text_of_block block =
  let unindent t = if String.starts_with ~prefix:" " t then String.sub t 1 (String.length t - 1) else t in
  String.trim (String.concat "\n" (List.rev_map unindent block))

(* A line without its comment, a -- outside a text. *)
let code_of line =
  let n = String.length line in
  let rec go i quoted =
    if i + 1 >= n then line
    else if line.[i] = '"' then go (i + 1) (not quoted)
    else if (not quoted) && line.[i] = '-' && line.[i + 1] = '-' then String.sub line 0 i
    else go (i + 1) quoted
  in
  String.trim (go 0 false)

(* What follows struct: Car { Mass, Speed = 0.0 }, also for the block form, whose fields are the lines up to end. The same
   for the methods of an interface. *)
let struct_signature r following =
  let rec fields = function
    | l :: rest -> (match code_of l with "end" -> [] | "" -> fields rest | f -> f :: fields rest)
    | [] -> []
  in
  let r = code_of r in
  if String.contains r '{' then r else Printf.sprintf "%s { %s }" r (String.concat ", " (fields following))

let entries src =
  let out = ref [] and block = ref [] and native = ref None in
  let add signature = out := { name = name_of signature; signature; text = text_of_block !block } :: !out in
  let close_native () =
    Option.iter add !native;
    native := None
  in
  let rec go = function
    | [] -> ()
    | line :: following ->
      let block_form = ref false in
      (match native_header line, comment_text line with
       | Some signature, _ ->
         close_native ();
         block := [];
         native := Some signature
       | None, Some text when String.length line > 0 && line.[0] = '-' -> block := text :: !block
       | _ ->
         close_native ();
         if is_definition line then begin
           let rest =
             match drop_prefix "defn " line, drop_prefix "struct " line, drop_prefix "interface " line with
             | Some r, _, _ -> signature_of r
             | _, Some r, _ | _, _, Some r ->
               block_form := not (String.contains r '{');
               struct_signature r following
             | None, None, None -> signature_of line
           in
           add rest
         end;
         block := []);
      (* The lines of a block are no definitions of their own. *)
      go (if !block_form then List.drop_while (fun l -> code_of l <> "end") following else following)
  in
  go (lines src);
  close_native ();
  List.rev !out

let public = Lexer.is_public

(* A method is public if its struct and its name are. *)
let public_name name =
  match Lexer.split_method name with
  | Some (sname, _, m) -> public sname && public m
  | None -> public name

let shown e = if e.text = "" then e.signature else e.signature ^ "\n\n" ^ e.text

(* Like [use], which reads the sources of KEPLER_STD when it is set. *)
let std name =
  match Sys.getenv_opt "KEPLER_STD" with
  | Some dir ->
    let path = Filename.concat dir (name ^ Package.suffix) in
    if Sys.file_exists path then Some (In_channel.with_open_bin path In_channel.input_all) else None
  | None -> List.assoc_opt name Embedded.files

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

(* The folder of a module of the project: a path as in a use, or the last part of a folder in use. No name leads out of the
   root: reading it takes no permission. *)
let folder_of w m =
  let path = Package.folder w.root m in
  if m = "" then None
  else if Package.is_dir path then (if Runtime.inside w.root path then Some path else None)
  else
    Hashtbl.fold
      (fun key _ found ->
         if found = None && Package.is_dir key && String.equal (Filename.basename key) m then Some key else found)
      w.loaded None

let package_sources w m =
  match folder_of w m with
  | Some dir -> List.map (fun path -> In_channel.with_open_bin path In_channel.input_all) (Package.files dir)
  | None -> []

(* A package is one module, whichever file holds a name. *)
let module_entries w m = std_entries m @ List.concat_map entries (package_sources w m)

(* The source whose top comment says what a module is for. *)
let module_source w m =
  match std m with
  | Some src -> Some src
  | None -> List.nth_opt (package_sources w m) 0

let find name es = List.find_opt (fun e -> String.equal e.name name) es

(* A comment at the top of a file says what the module is for. *)
let module_text src =
  let rec go acc = function
    | line :: rest when String.starts_with ~prefix:"--" line -> go (Option.get (comment_text line) :: acc) rest
    | _ -> text_of_block acc
  in
  go [] (String.split_on_char '\n' src)

let short_name n = match String.rindex_opt n '.' with Some i -> String.sub n (i + 1) (String.length n - i - 1) | None -> n

(* Without its module: num.Solve, date.Date.Year, date.Date.Parse. *)
let without_module name =
  match String.index_opt name '.' with
  | Some i -> String.sub name 0 i, String.sub name (i + 1) (String.length name - i - 1)
  | None -> "", name

let lookup w name =
  let native = find name (natives_entries ()) in
  let m, short = without_module name in
  let entry, short =
    match find name (std_entries "prelude") with
    | Some e -> Some e, name
    | None when m = "" -> native, name
    | None ->
      (match find short (module_entries w m) with
       | Some e -> Some e, short
       | None -> native, short)
  in
  if public_name short then Option.map shown entry else None

(* An instance method of the running program has no value to ask about: only its name leads to it. Two packages can each have
   a Rect.Area, so the file that asks comes first. *)
let program_method (ctx : ctx) name =
  let w = ctx.w in
  let wanted = Lexer.split_method name <> None && public_name name in
  let in_file (_, src) = if wanted then find name (entries src) else None in
  let asking =
    if ctx.site >= 0 && ctx.site < Dynarray.length w.sites then
      Seq.return (Dynarray.get w.files (Dynarray.get w.sites ctx.site).sfile)
    else Seq.empty
  in
  Option.map shown (Seq.find_map in_file (Seq.append asking (Dynarray.to_seq w.files)))

let modules w =
  let embedded = List.filter (fun m -> not (List.mem m not_modules)) (List.map fst Embedded.files) in
  "prelude" :: List.sort_uniq String.compare (embedded @ List.map fst w.native_modules)

let is_module w m = List.mem m (modules w) || package_sources w m <> []

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
  let written = List.filter_map (fun e -> if public_name e.name then Some (qualified e.name) else None) (module_entries w m) in
  List.sort_uniq String.compare (List.filter (fun n -> public (short_name n)) native_names @ written)

(* What a function value was defined as. A native knows only its short name. *)
let of_function w v =
  match v with
  | Fun { proto; _ } ->
    let _, src = Dynarray.get w.files proto.file in
    if public proto.pname then Option.map shown (find proto.pname (entries src)) else None
  | Native n ->
    (match lookup w n.nname with
     | Some text -> Some text
     | None ->
       let suffix = "." ^ n.nname in
       Option.map shown (List.find_opt (fun e -> String.ends_with ~suffix e.name) (natives_entries ())))
  | _ -> None

let doc ctx (a : t array) =
  let found =
    match a.(0) with
    | Text name ->
      (match lookup ctx.w name with
       | Some text -> Some text
       | None when is_module ctx.w name -> Option.map module_text (module_source ctx.w name)
       | None -> program_method ctx name)
    | v -> of_function ctx.w v
  in
  match found with Some text -> Text text | None -> Missing

let doc_names ctx (a : t array) =
  let found =
    match a with
    | [||] -> modules ctx.w
    | _ ->
      let m = Native.text_arg ctx "DocNames" a.(0) in
      if is_module ctx.w m then names ctx.w m else []
  in
  Arrays.list (Array.of_list (List.map (fun s -> Text s) found))

let natives =
  [ "Doc", Native.nat "Doc" 1 1 doc;
    "DocNames", Native.nat "DocNames" 0 1 doc_names ]

let first_line text = match String.index_opt text '\n' with Some i -> String.sub text 0 i | None -> text

(* The sentence after the signature of a name. *)
let summary w name =
  match lookup w name with
  | None -> ""
  | Some text ->
    (match String.index_opt text '\n' with
     | Some i -> first_line (String.trim (String.sub text i (String.length text - i)))
     | None -> "")

let command w args =
  w.root <- Package.root_of ".";
  let table rows =
    let width = List.fold_left (fun n (a, _) -> max n (String.length a)) 0 rows in
    List.iter (fun (a, b) -> print_endline (String.trim (Printf.sprintf "%-*s  %s" width a b))) rows
  in
  match args with
  | [] ->
    table (List.map (fun m -> m, first_line (module_text (Option.value (std m) ~default:""))) (modules w));
    0
  | [ name ] when is_module w name ->
    let head = module_text (Option.value (module_source w name) ~default:"") in
    if head <> "" && name <> "prelude" then print_endline (head ^ "\n");
    table (List.map (fun n -> n, summary w n) (names w name));
    0
  | [ name ] ->
    (match lookup w name with
     | Some text ->
       print_endline text;
       0
     | None ->
       prerr_endline (Messages.doc_missing name);
       1)
  | _ ->
    prerr_endline Messages.usage;
    2
