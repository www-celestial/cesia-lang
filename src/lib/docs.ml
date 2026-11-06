open Types

(* A documented name. Its lines are those of its documentation, numbered from 1, each as the words after -- would give them;
   its parts document its fields, parameters and result; its file and line are where it is defined. *)
type entry = {
  name : string;
  signature : string;
  text : string;
  lines : (int * string) list;
  parts : (string * string) list;
  file : string;
  line : int;
}

(* A (** ... *): the line it starts on, whether code comes before it there, the line it ends on, and its lines, newest first. *)
type doc = { first : int; after_code : bool; mutable last : int; mutable body : (int * string) list }

let rtrim s =
  let n = ref (String.length s) in
  while !n > 0 && s.[!n - 1] = ' ' do decr n done;
  String.sub s 0 !n

let blank s = String.trim s = ""

let piece s = if blank s then "" else " " ^ rtrim s

(* A source read for its documentation: its lines, the code of each without its comments, whether a line starts outside
   any comment, and the (** ... *) in their order. A text hides what looks like a comment.
   The lines of a (** ... *) lose the indentation of its first words, and its end loses its closing stars. *)
let scan src =
  let lines = Array.of_list (String.split_on_char '\n' src) in
  let codes = Array.make (Array.length lines) "" and outside = Array.make (Array.length lines) true in
  let docs = ref [] and depth = ref 0 and current = ref None and column = ref 0 in
  let add d k s =
    d.body <- (k + 1, piece s) :: d.body;
    d.last <- k + 1
  in
  Array.iteri
    (fun k line ->
       let n = String.length line and code = Buffer.create 80 in
       let at i c = i < n && line.[i] = c in
       outside.(k) <- !depth = 0;
       let from = ref 0 in
       if !current <> None then while !from < n && !from < !column && line.[!from] = ' ' do incr from done;
       let i = ref 0 and quoted = ref false in
       while !i < n do
         let c = line.[!i] in
         if !depth > 0 then begin
           if c = '(' && at (!i + 1) '*' then (incr depth; i := !i + 2)
           else if c = '*' && at (!i + 1) ')' then begin
             decr depth;
             (match !current with
              | Some d when !depth = 0 ->
                let upto = ref !i in
                while !upto > !from && line.[!upto - 1] = '*' do decr upto done;
                add d k (String.sub line !from (!upto - !from));
                docs := d :: !docs;
                current := None
              | _ -> ());
             i := !i + 2
           end
           else incr i
         end
         else if !quoted then (Buffer.add_char code c; quoted := c <> '"'; incr i)
         else if c = '"' then (Buffer.add_char code c; quoted := true; incr i)
         else if c = '(' && at (!i + 1) '*' then begin
           depth := 1;
           if at (!i + 2) '*' && not (at (!i + 3) ')' || at (!i + 3) '*') then begin
             column := if at (!i + 3) ' ' then !i + 4 else !i + 3;
             from := !column;
             current := Some { first = k + 1; after_code = String.trim (Buffer.contents code) <> ""; last = k + 1; body = [] }
           end;
           i := !i + 2
         end
         else (Buffer.add_char code c; incr i)
       done;
       (match !current with Some d -> add d k (String.sub line !from (max 0 (n - !from))) | None -> ());
       codes.(k) <- rtrim (Buffer.contents code))
    lines;
  lines, codes, outside, List.rev !docs

let is_name_char c =
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c >= '\128'

let name_end line from =
  let i = ref from in
  while !i < String.length line && is_name_char line.[!i] do incr i done;
  !i

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

(* The return type at the start of what follows the parameters, with its space: Rect, geo.Rect or Text?, which the end of the
   code or the = of a body follow. Else nothing. *)
let return_type rest =
  let n = String.length rest in
  let rec spaces i = if i < n && rest.[i] = ' ' then spaces (i + 1) else i in
  let a = spaces 0 in
  let b = name_end rest a in
  let b = if b > a && b < n && rest.[b] = '.' then name_end rest (b + 1) else b in
  let b = if b > a && b < n && rest.[b] = '?' then b + 1 else b in
  let after = String.trim (String.sub rest b (n - b)) in
  let is prefix = String.starts_with ~prefix after in
  let word = String.sub rest a (b - a) in
  if b > a && word <> "end" && (after = "" || (is "=" && not (is "==")) || is "(*") then " " ^ word else ""

(* Where the parenthesis that closes the first one of a line is, after an object if the line has one. *)
let head_close line =
  match String.index_from_opt line (Option.value (receiver_end line) ~default:0) '(' with
  | None -> None
  | Some start ->
    let n = String.length line in
    let rec go i depth quoted =
      if i >= n then None
      else
        match line.[i] with
        | '"' -> go (i + 1) depth (not quoted)
        | _ when quoted -> go (i + 1) depth quoted
        | '(' -> go (i + 1) (depth + 1) quoted
        | ')' when depth = 1 -> Some i
        | ')' -> go (i + 1) (depth - 1) quoted
        | _ -> go (i + 1) depth quoted
    in
    go start 0 false

let after_head line i = String.sub line (i + 1) (String.length line - i - 1)

(* A line up to the parenthesis that closes its first one, and its return type, which may be followed by = and a body. *)
let signature_of line =
  match head_close line with
  | None -> line
  | Some i -> String.sub line 0 (i + 1) ^ return_type (after_head line i)

(* A defn whose head ends its line, return type and all: its body is on the lines below. *)
let is_block_head r =
  match head_close r with
  | None -> false
  | Some i -> let rest = after_head r i in String.trim rest = "" || (return_type rest <> "" && not (String.contains rest '='))

(* (r Rect) IsEmpty() = ... or Rect.Unit() = ..., and not a call of a module at the start of a line: the name is after [i]. *)
let is_short_method line i =
  let from = i + 1 in
  let upto = name_end line from in
  upto > from && upto < String.length line && line.[upto] = '('
  &&
  let n = String.length (signature_of line) in
  let rest = String.trim (String.sub line n (String.length line - n)) in
  String.starts_with ~prefix:"=" rest && not (String.starts_with ~prefix:"==" rest)

(* Keyword = 1: a value named at the top of a file, whose name is all its signature. *)
let constant_end line =
  let i = name_end line 0 in
  if i > 0 && String.starts_with ~prefix:" = " (String.sub line i (String.length line - i)) then Some i else None

let is_definition line =
  String.starts_with ~prefix:"defn " line
  || String.starts_with ~prefix:"struct " line
  || String.starts_with ~prefix:"interface " line
  ||
  match receiver_end line with
  | Some i -> is_short_method line i
  | None ->
    let i = name_end line 0 in
    (i > 0 && i < String.length line && (line.[i] = '(' || (line.[i] = '.' && is_short_method line i)))
    || constant_end line <> None

let drop_prefix prefix s =
  if String.starts_with ~prefix s then Some (String.sub s (String.length prefix) (String.length s - String.length prefix))
  else None

(* The name in a signature: a module's name comes with its dot, and a method's with its struct, static or not. A keyword
   that is no word, ?, is its own name. *)
let name_of signature =
  match receiver_end signature with
  | Some i ->
    let sname = String.index signature ' ' + 1 in
    String.sub signature sname (i - 1 - sname) ^ "." ^ String.sub signature (i + 1) (name_end signature (i + 1) - i - 1)
  | None ->
    let i = name_end signature 0 in
    if i = 0 then signature
    else if i < String.length signature && signature.[i] = '.' then String.sub signature 0 (name_end signature (i + 1))
    else String.sub signature 0 i

let text_of_block block =
  let unindent t = if String.starts_with ~prefix:" " t then String.sub t 1 (String.length t - 1) else t in
  String.trim (String.concat "\n" (List.rev_map unindent block))

(* What follows struct: Car { Mass, Speed = 0.0 }, also for the block form, whose fields are the lines up to end. The same
   for the methods of an interface. *)
let struct_signature r following =
  let rec fields = function
    | l :: rest -> (match String.trim l with "end" -> [] | "" -> fields rest | f -> f :: fields rest)
    | [] -> []
  in
  let r = String.trim r in
  if String.contains r '{' then r else Printf.sprintf "%s { %s }" r (String.concat ", " (fields following))

(* How many parentheses a line of code leaves open, outside its texts. *)
let opened code =
  let n = ref 0 and quoted = ref false in
  String.iter (fun c -> if c = '"' then quoted := not !quoted else if not !quoted then (if c = '(' then incr n else if c = ')' then decr n)) code;
  !n

(* The lines of a definition's head joined, as if written on one: defn Scaled(r Rect, by Number) Rect. *)
let joined codes k h =
  if h = k then codes.(k)
  else begin
    let s = String.concat " " (List.map String.trim (Array.to_list (Array.sub codes k (h - k + 1)))) in
    let b = Buffer.create (String.length s) and quoted = ref false in
    let last () = if Buffer.length b = 0 then '(' else Buffer.nth b (Buffer.length b - 1) in
    String.iter
      (fun c ->
         if c = '"' then quoted := not !quoted;
         if !quoted || c = '"' then Buffer.add_char b c
         else if c = ' ' && (last () = '(' || last () = ' ') then ()
         else if c = ')' then begin
           while last () = ' ' || last () = ',' do Buffer.truncate b (Buffer.length b - 1) done;
           Buffer.add_char b c
         end
         else Buffer.add_char b c)
      s;
    Buffer.contents b
  end

let entries ?(file = "") src =
  let lines, codes, outside, docs = scan src in
  let count = Array.length lines in
  let starting k = List.find_opt (fun d -> d.first = k + 1) docs in
  let numbered d = List.rev d.body in
  let out = ref [] in
  let add ?(parts = []) k signature numbered =
    let text = text_of_block (List.rev_map snd numbered) in
    out := { name = name_of signature; signature; text; lines = numbered; parts; file; line = k + 1 } :: !out
  in
  (* A one-line definition: the (** *) at the end of its line, else the one just above it. *)
  let one_line k =
    match starting k with
    | Some d when d.after_code -> numbered d
    | _ ->
      (match List.find_opt (fun d -> d.last = k && not d.after_code) docs with
       | Some d -> numbered d
       | None -> [])
  in
  (* A block: the (** *) first in its body, after its head ends on line h. *)
  let inside h =
    let rec go j =
      if j >= count then []
      else match starting j with
        | Some d when not d.after_code -> numbered d
        | _ when blank codes.(j) -> go (j + 1)
        | _ -> []
    in
    go (h + 1)
  in
  (* The (** *) at the end of these lines, each under the name its line starts with. *)
  let parts_of name_on from upto =
    List.filter_map
      (fun j -> match starting j with Some d when d.after_code -> Some (name_on j, text_of_block (List.map snd d.body)) | _ -> None)
      (List.init (max 0 (upto - from + 1)) (fun i -> from + i))
  in
  let first_name s = let s = String.trim s in String.sub s 0 (name_end s 0) in
  let rec go k =
    if k < count then
      let code = codes.(k) in
      if not (outside.(k) && is_definition code) then go (k + 1)
      else
        (match drop_prefix "defn " code, drop_prefix "struct " code, drop_prefix "interface " code with
         | Some _, _, _ ->
           let rec head j open_ = let o = open_ + opened codes.(j) in if o <= 0 || j + 1 >= count then j else head (j + 1) o in
           let h = head k 0 in
           let r = Option.get (drop_prefix "defn " (joined codes k h)) in
           let signature = signature_of r in
           if is_block_head r then begin
             let name_on j = if String.starts_with ~prefix:")" (String.trim codes.(j)) || j = k then "result" else first_name codes.(j) in
             add ~parts:(parts_of name_on k h) k signature (inside h)
           end
           else add k signature (one_line k);
           go (k + 1)
         | _, Some r, _ | _, _, Some r ->
           if String.contains r '{' then begin
             add k (struct_signature r []) (one_line k);
             go (k + 1)
           end
           else begin
             let rec close j = if j >= count || String.trim codes.(j) = "end" then j else close (j + 1) in
             let e = close (k + 1) in
             add ~parts:(parts_of (fun j -> first_name codes.(j)) (k + 1) (e - 1))
               k (struct_signature r (Array.to_list (Array.sub codes (k + 1) (count - k - 1)))) (inside k);
             go (e + 1)
           end
         | None, None, None ->
           let signature = match constant_end code with Some i -> String.sub code 0 i | None -> signature_of code in
           add k signature (one_line k);
           go (k + 1))
  in
  (* A file of natives has no code but its uses: each of its (** *) starts with the signature of the native it documents, or
     with the one word it documents, as keywords.ce does. *)
  if Array.for_all (fun c -> blank c || String.starts_with ~prefix:"use " c) codes then
    List.iter
      (fun d ->
         match numbered d with
         | (_, s) :: rest
           when (let s = String.trim s in
                 let i = name_end s 0 in
                 s <> "" && ((not (String.contains s ' ')) || (i > 0 && (s.[i] = '(' || s.[i] = '.')))) ->
           add (d.first - 1) (String.trim s) rest
         | _ -> ())
      docs;
  go 0;
  List.rev !out

let public = Lexer.is_public

(* A method is public if its struct and its name are. *)
let public_name name =
  match Lexer.split_method name with
  | Some (sname, _, m) -> public sname && public m
  | None -> public name

(* The signature, the text, then the parts: two spaces, the name padded to the longest one, two spaces and its words. *)
let shown e =
  let width = List.fold_left (fun w (n, _) -> max w (String.length n)) 0 e.parts in
  let parts = String.concat "\n" (List.map (fun (n, t) -> Printf.sprintf "  %-*s  %s" width n t) e.parts) in
  String.concat "\n\n" (List.filter (( <> ) "") [ e.signature; e.text; parts ])

(* The lines of the documentation that are examples: indented, and run by cesia test. *)
let examples src =
  List.concat_map (fun e -> List.filter (fun (_, t) -> String.starts_with ~prefix:"  " t) e.lines) (entries src)

(* Like [use], which reads the sources of CESIA_STD when it is set. *)
let std name =
  match Sys.getenv_opt "CESIA_STD" with
  | Some dir ->
    let path = Filename.concat dir (name ^ Package.suffix) in
    if Sys.file_exists path then Some (In_channel.with_open_bin path In_channel.input_all) else None
  | None -> List.assoc_opt name Embedded.files

let language = [ "prelude"; "natives"; "keywords" ]

(* An editor asks often, so a file of std/ is read once. *)
let read = Hashtbl.create 32

let std_entries name =
  match Hashtbl.find_opt read name with
  | Some es -> es
  | None ->
    let file = "std/" ^ name ^ Package.suffix in
    let es = entries ~file (Option.value (std name) ~default:"") in
    Hashtbl.add read name es;
    es

let natives_entries () = std_entries "natives"

(* The project whose documentation is asked for. A tool runs outside any, so that it never uses a project's copies, and
   documents the one it runs in. *)
let root w = if String.contains w.root '\000' then Package.root_of "." else w.root

(* A file of the project, from its root. *)
let from_root w path =
  let prefix = root w ^ Filename.dir_sep in
  Option.value (drop_prefix prefix path) ~default:path

(* The folder of a module of the project: a path as in a use, or the last part of a folder in use. No name leads out of the
   root: reading it takes no permission. *)
let folder_of w m =
  let path = Package.folder (root w) m in
  if m = "" then None
  else if Package.is_dir path then (if Runtime.inside (root w) path then Some path else None)
  else
    Hashtbl.fold
      (fun key _ found ->
         if found = None && Package.is_dir key && String.equal (Filename.basename key) m then Some key else found)
      w.loaded None

let read_all w paths = List.map (fun path -> from_root w path, In_channel.with_open_bin path In_channel.input_all) paths

let package_sources w m = match folder_of w m with Some dir -> read_all w (Package.files dir) | None -> []

(* std/num is the library num: its name in the code, and in std/ of Cesia. *)
let bare m = Option.value (drop_prefix "std/" m) ~default:m

(* The sources of a module that aren't Cesia's own, as use finds them: a folder of the project, or the copy of a library in
   std/. A name of the code, num, is the library when no folder of the project has it. *)
let own_sources w m =
  let copy name =
    match Package.files (Filename.concat (Filename.concat (root w) "std") name) with [] -> None | files -> Some (read_all w files)
  in
  match drop_prefix "std/" m with
  | Some name -> copy name
  | None -> (match package_sources w m with [] -> copy m | srcs -> Some srcs)

(* A package is one module, whichever file holds a name. *)
let module_entries w m =
  match own_sources w m with
  | Some srcs -> List.concat_map (fun (file, src) -> entries ~file src) srcs
  | None -> std_entries (bare m)

(* The source whose top comment says what a module is for. *)
let module_source w m =
  match own_sources w m with
  | Some ((_, src) :: _) -> Some src
  | _ -> std (bare m)

let find name es = List.find_opt (fun e -> String.equal e.name name) es

(* The first (** *) of a file, before any code, says what the module is for. *)
let module_text src =
  let _, codes, _, docs = scan src in
  match docs with
  | d :: _ when (not d.after_code) && Array.for_all blank (Array.sub codes 0 (d.first - 1)) -> text_of_block (List.map snd d.body)
  | _ -> ""

(* What a module is for: the top of its source, or for a module of the binary the block of std/natives.ce named after it. *)
let module_about w m =
  match module_source w m with
  | Some src -> module_text src
  | None -> (match find (bare m) (natives_entries ()) with Some e -> e.text | None -> "")

let short_name n = match String.rindex_opt n '.' with Some i -> String.sub n (i + 1) (String.length n - i - 1) | None -> n

(* Without its module: num.Solve, date.Date.Year, date.Date.Parse. *)
let without_module name =
  match String.index_opt name '.' with
  | Some i -> String.sub name 0 i, String.sub name (i + 1) (String.length name - i - 1)
  | None -> "", name

(* The module that a name in the code leads to, as DocNames lists it: shapes is src/shapes, num is std/num. *)
let module_name w m =
  match folder_of w m with
  | Some dir when package_sources w m <> [] -> from_root w dir
  | _ -> "std/" ^ m

(* The documentation of a name or a keyword, its module as DocNames lists it (none for a keyword), and whether it is built
   into the binary: a keyword, or a native of src/std/natives.ce, in OCaml. *)
let found_entry w name =
  let native = find name (natives_entries ()) in
  let m, short = without_module name in
  match if List.exists (String.equal name) Lexer.words then find name (std_entries "keywords") else None with
  | Some e -> Some (e, lazy "", true)
  | None ->
    let entry, short, md, builtin =
      match find name (std_entries "prelude") with
      | Some e -> Some e, name, lazy "prelude", false
      | None when m = "" -> native, name, lazy "prelude", true
      | None ->
        (match find short (module_entries w m) with
         | Some e -> Some e, short, lazy (module_name w m), false
         | None -> native, short, lazy ("std/" ^ m), true)
    in
    if public_name short then Option.map (fun e -> e, md, builtin) entry else None

let found w name = Option.map (fun (e, _, builtin) -> shown e, builtin) (found_entry w name)

let lookup w name = Option.map fst (found w name)

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

(* The packages of the project: the folders of its source folders that hold code. *)
let project_modules w =
  let r = root w in
  let packages dir =
    let path = Filename.concat r dir in
    let names = if Package.is_dir path then List.sort String.compare (Array.to_list (Sys.readdir path)) else [] in
    List.filter_map (fun name -> if Package.files (Filename.concat path name) <> [] then Some (dir ^ "/" ^ name) else None) names
  in
  if Sys.file_exists (Filename.concat r Package.project_file) then List.concat_map packages (Package.sources r) else []

(* The modules of Cesia itself: its libraries and the modules of the binary. *)
let own_modules w =
  List.map (fun m -> "std/" ^ m)
    (List.filter_map (fun (m, _) -> if List.mem m language then None else Some m) Embedded.files @ List.map fst w.native_modules)

let modules w = "prelude" :: List.sort_uniq String.compare (own_modules w @ project_modules w)

let is_module w m = m = "prelude" || List.mem m (own_modules w) || package_sources w m <> [] || own_sources w m <> None

(* What a name of a module starts with: the name of the code, num.Solve or shapes.Unit, when it leads back to the module; else
   its path, tests/mods/geo.Rect. *)
let qualifier w m =
  match drop_prefix "std/" m with
  | Some name -> name
  | None ->
    let alias = Filename.basename m in
    if folder_of w alias <> None && folder_of w alias = folder_of w m then alias else m

let names w m =
  let alias = qualifier w m in
  let qualified n = if m = "prelude" then n else alias ^ "." ^ n in
  let native_names =
    if m = "prelude" then
      List.map fst w.modules.(0).mnames
      @ List.filter_map (fun e -> if String.contains e.name '.' then None else Some e.name) (natives_entries ())
    else
      List.map (fun (n, _) -> alias ^ "." ^ n) (Option.value (List.assoc_opt (bare m) w.native_modules) ~default:[])
      @ List.filter_map (fun e -> Option.map (fun _ -> e.name) (drop_prefix (alias ^ ".") e.name)) (natives_entries ())
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
       | None when is_module ctx.w name -> Some (module_about ctx.w name)
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

let entry_keys = Trie.names [| "Name"; "Module"; "Signature"; "Text"; "Parts"; "Examples"; "Builtin"; "File"; "Line" |]
let part_keys = Trie.names [| "Name"; "Text" |]

(* cesia.DocEntry: what the site shows of a name or a keyword, its examples apart from its text. *)
let doc_entry ctx (a : t array) =
  let name = Native.text_arg ctx "cesia.DocEntry" a.(0) in
  match found_entry ctx.w name with
  | None -> Missing
  | Some (e, m, builtin) ->
    let example (_, t) = String.starts_with ~prefix:"  " t in
    let list f l = Arrays.list (Array.of_list (List.map f l)) in
    let text = text_of_block (List.rev_map snd (List.filter (fun l -> not (example l)) e.lines)) in
    let examples = list (fun (_, t) -> Text (String.trim t)) (List.filter example e.lines) in
    let parts = list (fun (n, t) -> Trie.record part_keys [| Text n; Text t |]) e.parts in
    Trie.record entry_keys
      [| Text name; Text (Lazy.force m); Text e.signature; Text text; parts; examples; Value.of_bool builtin; Text e.file; Int e.line |]

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
    table (List.map (fun m -> m, first_line (module_about w m)) (modules w));
    0
  | [ name ] when is_module w name ->
    let head = module_about w name in
    if head <> "" && name <> "prelude" then print_endline (head ^ "\n");
    table (List.map (fun n -> n, summary w n) (names w name));
    0
  | [ name ] ->
    (match found w name with
     | Some (text, builtin) ->
       print_endline text;
       (* Its code is in the binary: no source of Cesia to read. *)
       if builtin then print_endline "\nBuilt into Cesia.";
       0
     | None ->
       prerr_endline (Messages.doc_missing name);
       1)
  | _ ->
    prerr_endline Messages.usage;
    2
