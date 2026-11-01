type value = Text of string | Flag of bool | Texts of string list
type entry = { key : string; value : value; line : int }
type table = { path : string list; start : int; entries : entry list }

exception Refused of int * string

type cursor = { src : string; mutable at : int; mutable line : int }

(* Every name of the file, as a tree: keys are bare, so a dotted text would be the same, but its cost grows with the
   depth of a header. *)
type kind = Key | Table | Implicit
type node = { mutable kind : kind; children : (string, node) Hashtbl.t }

let refuse c reason = raise (Refused (c.line, reason))
let unsupported c what = refuse c (Messages.toml_unsupported what)
let expected c what = refuse c (Messages.toml_expected what)

(* A zero byte is refused first, so here it can only mean the end of the text. *)
let peek c = if c.at < String.length c.src then c.src.[c.at] else '\000'
let advance c = c.at <- c.at + 1

let looking_at c text =
  let n = String.length text in
  c.at + n <= String.length c.src && String.equal (String.sub c.src c.at n) text

let check_bytes src =
  List.iteri
    (fun i line -> if not (String.is_valid_utf_8 line) then raise (Refused (i + 1, Messages.toml_utf8)))
    (String.split_on_char '\n' src);
  let n = String.length src and line = ref 1 in
  String.iteri
    (fun i ch ->
       let line_end = ch = '\r' && i + 1 < n && src.[i + 1] = '\n' in
       if ch = '\n' then incr line
       else if (ch < ' ' && ch <> '\t' && not line_end) || ch = '\127' then
         raise (Refused (!line, Messages.toml_control)))
    src

let skip_spaces c =
  while peek c = ' ' || peek c = '\t' do
    advance c
  done

let skip_comment c =
  if peek c = '#' then
    while peek c <> '\n' && peek c <> '\000' do
      advance c
    done

let next_line c =
  advance c;
  c.line <- c.line + 1

(* Spaces, comments and line ends, between statements and inside an array. *)
let rec skip_blank c =
  skip_spaces c;
  skip_comment c;
  match peek c with
  | '\r' -> advance c; skip_blank c
  | '\n' -> next_line c; skip_blank c
  | _ -> ()

(* After a header or a value: nothing but a comment. *)
let end_line c =
  skip_spaces c;
  skip_comment c;
  if peek c = '\r' then advance c;
  match peek c with
  | '\n' -> next_line c
  | '\000' -> ()
  | _ -> expected c "the end of the line"

let is_bare ch =
  (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch = '_' || ch = '-'

let word c =
  let start = c.at in
  while is_bare (peek c) do
    advance c
  done;
  String.sub c.src start (c.at - start)

let bare_key c =
  match word c with
  | "" -> if peek c = '"' || peek c = '\'' then unsupported c "Quoted keys" else expected c "a key"
  | key -> key

let literal_string c =
  advance c;
  let start = c.at in
  while peek c <> '\'' do
    if peek c = '\n' || peek c = '\000' then refuse c Messages.toml_string_open;
    advance c
  done;
  let text = String.sub c.src start (c.at - start) in
  advance c;
  text

let basic_string c =
  advance c;
  let text = Buffer.create 32 in
  let rec go () =
    match peek c with
    | '"' -> advance c
    | '\n' | '\000' -> refuse c Messages.toml_string_open
    | '\\' ->
      advance c;
      (match peek c with
       | '\\' | '"' -> Buffer.add_char text (peek c)
       | 'n' -> Buffer.add_char text '\n'
       | 't' -> Buffer.add_char text '\t'
       | 'r' -> Buffer.add_char text '\r'
       | '\n' | '\r' | '\000' -> refuse c Messages.toml_string_open
       | ch -> refuse c (Messages.toml_escape ch));
      advance c;
      go ()
    | ch ->
      Buffer.add_char text ch;
      advance c;
      go ()
  in
  go ();
  Buffer.contents text

let string_value c =
  if looking_at c "\"\"\"" || looking_at c "'''" then unsupported c "Multi-line strings"
  else if peek c = '"' then basic_string c
  else literal_string c

let array_value c =
  advance c;
  let rec go items =
    skip_blank c;
    match peek c with
    | ']' -> advance c; List.rev items
    | '\000' -> refuse c Messages.toml_array_open
    | '[' -> unsupported c "Nested arrays"
    | '"' | '\'' ->
      let item = string_value c in
      skip_blank c;
      (match peek c with
       | ',' -> advance c; go (item :: items)
       | ']' -> advance c; List.rev (item :: items)
       | '\000' -> refuse c Messages.toml_array_open
       | _ -> expected c "a comma or ]")
    | _ -> refuse c Messages.toml_strings_only
  in
  go []

let value c =
  match peek c with
  | '"' | '\'' -> Text (string_value c)
  | '[' -> Texts (array_value c)
  | '{' -> unsupported c "Inline tables"
  | first ->
    let number = (first >= '0' && first <= '9') || first = '+' || first = '-' in
    (match word c with
     | "true" -> Flag true
     | "false" -> Flag false
     | "inf" | "nan" -> unsupported c "Numbers and dates"
     | _ -> if number then unsupported c "Numbers and dates" else expected c "a value")

let header c =
  if looking_at c "[[" then unsupported c "Arrays of tables";
  advance c;
  let rec parts path =
    skip_spaces c;
    let part = bare_key c in
    skip_spaces c;
    match peek c with
    | '.' -> advance c; parts (part :: path)
    | ']' -> advance c; List.rev (part :: path)
    | _ -> expected c "]"
  in
  parts []

let new_node kind = { kind; children = Hashtbl.create 4 }

let child parent part =
  match Hashtbl.find_opt parent.children part with
  | Some node -> node
  | None ->
    let node = new_node Implicit in
    Hashtbl.replace parent.children part node;
    node

let twice c path = refuse c (Messages.toml_twice (String.concat "." path))

(* The node of a header. A key can't be one of its prefixes, and a table is only defined once. *)
let enter c root path =
  let rec walk node seen = function
    | [] -> node
    | part :: rest ->
      let next = child node part and seen = part :: seen in
      if next.kind = Key then twice c (List.rev seen);
      walk next seen rest
  in
  let node = walk root [] path in
  if node.kind = Table then twice c path;
  node.kind <- Table;
  node

let read c =
  let root = new_node Table in
  let rec statements tables table node =
    skip_blank c;
    let close () =
      if table.path <> [] || table.entries <> [] then { table with entries = List.rev table.entries } :: tables
      else tables
    in
    match peek c with
    | '\000' -> List.rev (close ())
    | '[' ->
      let start = c.line in
      let path = header c in
      let node = enter c root path in
      end_line c;
      statements (close ()) { path; start; entries = [] } node
    | _ ->
      let line = c.line in
      let key = bare_key c in
      skip_spaces c;
      if peek c = '.' then unsupported c "Dotted keys";
      if peek c <> '=' then expected c "=";
      advance c;
      skip_spaces c;
      if Hashtbl.mem node.children key then twice c (table.path @ [ key ]);
      Hashtbl.replace node.children key (new_node Key);
      let value = value c in
      end_line c;
      statements tables { table with entries = { key; value; line } :: table.entries } node
  in
  statements [] { path = []; start = 1; entries = [] } root

let parse src =
  let c = { src; at = 0; line = 1 } in
  match
    check_bytes src;
    read c
  with
  | tables -> Ok tables
  | exception Refused (line, reason) -> Error (line, reason)
