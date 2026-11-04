open Pos

type tok =
  | INT of int
  | FLOAT of float
  | TEXT of part list
  | NAME of string
  | IF | ELSE | END | FOR | IN | WHILE | BREAK | RETURN | DEFN | MATCH | STRUCT | INTERFACE
  | AND | OR | NOT | THEN | USE | TRUE | FALSE | MISSING
  | PLUS | MINUS | STAR | SLASH | CARET
  | ASSIGN | EQEQ | NE | LT | LE | GT | GE
  | PLUSEQ | MINUSEQ | STAREQ | SLASHEQ
  | ARROW | COLON | SEMI | COMMA | DOT | QUESTION
  | LP | RP | LB | RB | LC | RC
  | NL
  | EOF

and token = { t : tok; pos : Pos.t; sp : bool }
and part = Plain of string | Code of token array

let keyword = function
  | "if" -> Some IF | "else" -> Some ELSE | "end" -> Some END | "for" -> Some FOR | "in" -> Some IN
  | "while" -> Some WHILE | "break" -> Some BREAK | "return" -> Some RETURN | "defn" -> Some DEFN
  | "match" -> Some MATCH | "struct" -> Some STRUCT | "interface" -> Some INTERFACE | "and" -> Some AND | "or" -> Some OR
  | "not" -> Some NOT | "then" -> Some THEN | "use" -> Some USE | "true" -> Some TRUE | "false" -> Some FALSE
  | "missing" -> Some MISSING
  | _ -> None

type st = {
  src : string;
  file : string;
  mutable i : int;
  mutable line : int;
  mutable line_start : int;
  mutable seen_i : int;  (* last point of column computation *)
  mutable seen_col : int;
}

let is_digit c = c >= '0' && c <= '9'
let is_name_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' || c >= '\128'
let is_name c = is_name_start c || is_digit c

let is_public name = name <> "" && name.[0] >= 'A' && name.[0] <= 'Z'

(* Inside the core, the name of a method says its kind: Rect.Area, or Rect:Square when static. Gives the struct, whether it is
   static, and the method. A program only ever sees a dot: a static method's function is named Rect.Square. *)
let split_method text =
  let n = String.length text in
  let rec go i =
    if i >= n then None
    else
      match text.[i] with
      | '.' | ':' -> Some (String.sub text 0 i, text.[i] = ':', String.sub text (i + 1) (n - i - 1))
      | _ -> go (i + 1)
  in
  go 0

(* The words of a name with a _, joined by capitals, for the hint of its error. *)
let joined ~public name =
  let words = List.filter (fun w -> w <> "") (String.split_on_char '_' name) in
  let cap = String.concat "" (List.map String.capitalize_ascii words) in
  if public then cap else String.uncapitalize_ascii cap

(* The column in code points: a UTF-8 continuation byte doesn't count. *)
let pos_at st i =
  if st.seen_i < st.line_start then begin
    st.seen_i <- st.line_start;
    st.seen_col <- 1
  end;
  for k = st.seen_i to i - 1 do
    if Char.code st.src.[k] land 0xC0 <> 0x80 then st.seen_col <- st.seen_col + 1
  done;
  st.seen_i <- i;
  Pos.make st.line st.seen_col

let error st pos (m : Messages.t) =
  raise (Load_error { file = st.file; pos; kind = "syntax"; text = m.text; hint = m.hint })

(* A name, or a keyword. The lone _ is the wildcard of a pattern. *)
let word_token st pos word =
  if Option.is_some (String.index_opt word '_') && word <> "_" then
    error st pos (Messages.underscore_name word (joined ~public:false word) (joined ~public:true word));
  match keyword word with Some k -> k | None -> NAME word

let peek_at st k = if st.i + k < String.length st.src then st.src.[st.i + k] else '\000'

let new_line st =
  st.line <- st.line + 1;
  st.line_start <- st.i

(* (* ... *), which can hold another one. *)
let block_comment st =
  let pos = pos_at st st.i in
  let n = String.length st.src in
  let depth = ref 0 in
  let looking = ref true in
  while !looking do
    if st.i >= n then error st pos Messages.comment_not_closed
    else if st.src.[st.i] = '(' && peek_at st 1 = '*' then begin
      incr depth;
      st.i <- st.i + 2
    end
    else if st.src.[st.i] = '*' && peek_at st 1 = ')' then begin
      decr depth;
      st.i <- st.i + 2;
      if !depth = 0 then looking := false
    end
    else begin
      let line_end = st.src.[st.i] = '\n' in
      st.i <- st.i + 1;
      if line_end then new_line st
    end
  done

let number st start_pos sp =
  let s = st.src and n = String.length st.src in
  let start = st.i in
  let digits () = while st.i < n && (is_digit s.[st.i] || s.[st.i] = '_') do st.i <- st.i + 1 done in
  let clean () = String.concat "" (String.split_on_char '_' (String.sub s start (st.i - start))) in
  if s.[st.i] = '0' && (peek_at st 1 = 'x' || peek_at st 1 = 'X') then begin
    st.i <- st.i + 2;
    while st.i < n && (is_digit s.[st.i] || (Char.lowercase_ascii s.[st.i] >= 'a' && Char.lowercase_ascii s.[st.i] <= 'f') || s.[st.i] = '_') do
      st.i <- st.i + 1
    done;
    let text = clean () in
    (* OCaml reads 0x7fff... up to 2 * max_int + 1, going through negatives. *)
    match int_of_string_opt text with
    | Some v when v >= 0 -> { t = INT v; pos = start_pos; sp }
    | _ -> error st start_pos (Messages.number_too_big text)
  end else begin
    digits ();
    let is_float = ref false in
    if st.i + 1 < n && s.[st.i] = '.' && is_digit s.[st.i + 1] then begin
      is_float := true;
      st.i <- st.i + 1;
      digits ()
    end;
    if st.i < n && (s.[st.i] = 'e' || s.[st.i] = 'E') then begin
      let k = if peek_at st 1 = '+' || peek_at st 1 = '-' then 2 else 1 in
      if is_digit (peek_at st k) then begin
        is_float := true;
        st.i <- st.i + k;
        digits ()
      end
    end;
    let text = clean () in
    if !is_float then { t = FLOAT (float_of_string text); pos = start_pos; sp }
    else
      match int_of_string_opt text with
      | Some v -> { t = INT v; pos = start_pos; sp }
      | None -> error st start_pos (Messages.number_too_big text)
  end

let rec scan st ~in_code : token array =
  let out = Dynarray.create () in
  let s = st.src and n = String.length st.src in
  let sp = ref true in
  let depth = ref 0 in
  let fin = ref false in
  let push t pos = Dynarray.add_last out { t; pos; sp = !sp }; sp := false in
  while not !fin do
    if st.i >= n then begin
      if in_code then error st (pos_at st st.i) Messages.text_not_closed;
      fin := true
    end else begin
      let c = s.[st.i] in
      match c with
      | ' ' | '\t' | '\r' -> st.i <- st.i + 1; sp := true
      | '\n' ->
        let pos = pos_at st st.i in
        st.i <- st.i + 1;
        new_line st;
        push NL pos;
        sp := true
      | '-' when peek_at st 1 = '-' -> error st (pos_at st st.i) Messages.comment_dashes
      | '(' when peek_at st 1 = '*' ->
        block_comment st;
        sp := true
      | '"' ->
        let pos = pos_at st st.i in
        let parts = text st pos in
        push (TEXT parts) pos
      | _ when is_digit c ->
        let pos = pos_at st st.i in
        let tok = number st pos !sp in
        Dynarray.add_last out tok;
        sp := false
      | _ when is_name_start c ->
        let start = st.i in
        let pos = pos_at st st.i in
        while st.i < n && is_name s.[st.i] do st.i <- st.i + 1 done;
        push (word_token st pos (String.sub s start (st.i - start))) pos
      | _ ->
        let pos = pos_at st st.i in
        let c2 = peek_at st 1 in
        let two t = st.i <- st.i + 2; push t pos in
        let one t = st.i <- st.i + 1; push t pos in
        match c, c2 with
        | '=', '=' -> two EQEQ
        | '!', '=' -> two NE
        | '<', '=' -> two LE
        | '>', '=' -> two GE
        | '-', '>' -> two ARROW
        | '+', '=' -> two PLUSEQ
        | '-', '=' -> two MINUSEQ
        | '*', '=' -> two STAREQ
        | '/', '=' -> two SLASHEQ
        | '+', _ -> one PLUS
        | '-', _ -> one MINUS
        | '*', _ -> one STAR
        | '/', _ -> one SLASH
        | '^', _ -> one CARET
        | '=', _ -> one ASSIGN
        | '<', _ -> one LT
        | '>', _ -> one GT
        | ':', _ -> one COLON
        | ';', _ -> one SEMI
        | ',', _ -> one COMMA
        | '.', _ -> one DOT
        | '?', _ -> one QUESTION
        | '(', _ -> incr depth; one LP
        | ')', _ ->
          if in_code && !depth = 0 then begin
            st.i <- st.i + 1;
            fin := true
          end else begin
            decr depth;
            one RP
          end
        | '[', _ -> one LB
        | ']', _ -> one RB
        | '{', _ -> one LC
        | '}', _ -> one RC
        | _ -> error st pos (Messages.unexpected_char c)
    end
  done;
  push NL (pos_at st st.i);
  push EOF (pos_at st st.i);
  Dynarray.to_array out

and text st start_pos =
  let s = st.src and n = String.length st.src in
  st.i <- st.i + 1;
  let parts = ref [] in
  let run = Buffer.create 16 in
  let flush () =
    if Buffer.length run > 0 then begin
      parts := Plain (Buffer.contents run) :: !parts;
      Buffer.clear run
    end
  in
  let two c =
    Buffer.add_char run c;
    st.i <- st.i + 2
  in
  let fin = ref false in
  while not !fin do
    if st.i >= n then error st start_pos Messages.text_not_closed;
    match s.[st.i], peek_at st 1 with
    | '\\', 'n' -> two '\n'
    | '\\', 't' -> two '\t'
    | '\\', 'r' -> two '\r'
    | '\\', (('\\' | '"') as c) | '"', ('"' as c) | '$', ('$' as c) -> two c
    | '"', _ ->
      st.i <- st.i + 1;
      fin := true
    | '$', '(' ->
      flush ();
      st.i <- st.i + 2;
      parts := Code (scan st ~in_code:true) :: !parts
    | '$', c2 when is_name_start c2 ->
      flush ();
      st.i <- st.i + 1;
      let pos = pos_at st st.i in
      let start = st.i in
      while st.i < n && is_name s.[st.i] do st.i <- st.i + 1 done;
      let tok = word_token st pos (String.sub s start (st.i - start)) in
      parts := Code [| { t = tok; pos; sp = false }; { t = NL; pos; sp = false }; { t = EOF; pos; sp = false } |] :: !parts
    | c, _ ->
      Buffer.add_char run c;
      st.i <- st.i + 1;
      if c = '\n' then new_line st
  done;
  flush ();
  match List.rev !parts with [] -> [ Plain "" ] | l -> l

let tokens ~file src =
  if not (String.is_valid_utf_8 src) then
    raise (Load_error { file; pos = Pos.make 1 1; kind = "syntax"; text = Messages.invalid_utf8.text; hint = None });
  let start = if String.starts_with ~prefix:"\xef\xbb\xbf" src then 3 else 0 in
  let st = { src; file; i = start; line = 1; line_start = start; seen_i = start; seen_col = 1 } in
  scan st ~in_code:false
