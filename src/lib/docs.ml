open Types

(* A documented name. Its lines are those of its documentation, numbered from 1, each as the words after -- would give them;
   its parts document its fields, parameters and result. *)
type entry = { name : string; signature : string; text : string; lines : (int * string) list; parts : (string * string) list }

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

let entries src =
  let lines, codes, outside, docs = scan src in
  let count = Array.length lines in
  let starting k = List.find_opt (fun d -> d.first = k + 1) docs in
  let numbered d = List.rev d.body in
  let out = ref [] in
  let add ?(parts = []) signature numbered =
    let text = text_of_block (List.rev_map snd numbered) in
    out := { name = name_of signature; signature; text; lines = numbered; parts } :: !out
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
             add ~parts:(parts_of name_on k h) signature (inside h)
           end
           else add signature (one_line k);
           go (k + 1)
         | _, Some r, _ | _, _, Some r ->
           if String.contains r '{' then begin
             add (struct_signature r []) (one_line k);
             go (k + 1)
           end
           else begin
             let rec close j = if j >= count || String.trim codes.(j) = "end" then j else close (j + 1) in
             let e = close (k + 1) in
             add ~parts:(parts_of (fun j -> first_name codes.(j)) (k + 1) (e - 1))
               (struct_signature r (Array.to_list (Array.sub codes (k + 1) (count - k - 1)))) (inside k);
             go (e + 1)
           end
         | None, None, None ->
           add (signature_of code) (one_line k);
           go (k + 1))
  in
  (* A file of natives has no code but its uses: each of its (** *) starts with the signature of the native it documents. *)
  if Array.for_all (fun c -> blank c || String.starts_with ~prefix:"use " c) codes then
    List.iter
      (fun d ->
         match numbered d with
         | (_, s) :: rest when (let s = String.trim s in let i = name_end s 0 in i > 0 && (i = String.length s || s.[i] = '(' || s.[i] = '.')) ->
           add (String.trim s) rest
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

(* The name in the code: rope for pkg/rope. *)
let code_name m = Option.value (Package.library m) ~default:m

(* The sources of a module that aren't Cesia's own, as use finds them: a folder of the project, or the copy of a library in
   pkg/. A name of the code, rope, is the library when no folder of the project has it. *)
let own_sources w m =
  let copy name =
    match Package.files (Filename.concat (Filename.concat w.root "pkg") name) with
    | [] -> None
    | files -> Some (List.map (fun path -> In_channel.with_open_bin path In_channel.input_all) files)
  in
  match Package.library m with
  | Some name -> copy name
  | None -> (match package_sources w m with [] -> copy m | srcs -> Some srcs)

(* A package is one module, whichever file holds a name. *)
let module_entries w m =
  match own_sources w m with
  | Some srcs -> List.concat_map entries srcs
  | None -> std_entries (code_name m)

(* The source whose top comment says what a module is for. *)
let module_source w m =
  match own_sources w m with
  | Some (src :: _) -> Some src
  | _ -> std (code_name m)

let find name es = List.find_opt (fun e -> String.equal e.name name) es

(* The first (** *) of a file, before any code, says what the module is for. *)
let module_text src =
  let _, codes, _, docs = scan src in
  match docs with
  | d :: _ when (not d.after_code) && Array.for_all blank (Array.sub codes 0 (d.first - 1)) -> text_of_block (List.map snd d.body)
  | _ -> ""

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
  let libraries = List.filter_map (fun (m, _) -> if List.mem m not_modules then None else Some ("pkg/" ^ m)) Embedded.files in
  "prelude" :: List.sort_uniq String.compare (libraries @ List.map fst w.native_modules)

let is_library m = (not (List.mem m not_modules)) && std m <> None

let is_module w m =
  List.mem m (modules w) || is_library (code_name m) || package_sources w m <> [] || own_sources w m <> None

let names w m =
  let qualified n = if m = "prelude" then n else code_name m ^ "." ^ n in
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
    table (List.map (fun m -> m, first_line (module_text (Option.value (module_source w m) ~default:""))) (modules w));
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
