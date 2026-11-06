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
  | ARROW | COLON | SEMI | COMMA | DOT | DOTDOT | QUESTION | BANG
  | LP | RP | LB | RB | LC | RC
  | NL
  | EOF

and token = { t : tok; pos : Pos.t; sp : bool }
and part = Plain of string | Code of token array

(* The reserved words, in one list: the lexer reads it, and cesia.Keywords gives it, with the words below, to the highlighter
   and the docs. *)
let keywords =
  [ "if", IF; "else", ELSE; "end", END; "for", FOR; "in", IN; "while", WHILE; "break", BREAK; "return", RETURN; "defn", DEFN;
    "match", MATCH; "struct", STRUCT; "interface", INTERFACE; "and", AND; "or", OR; "not", NOT; "then", THEN; "use", USE;
    "true", TRUE; "false", FALSE; "missing", MISSING ]

(* By first letter, each word with its token ready: every name the lexer meets is looked up, those of std/ at each use. *)
let by_first =
  let t = Array.make 256 [] in
  List.iter (fun (w, k) -> t.(Char.code w.[0]) <- (w, Some k) :: t.(Char.code w.[0])) keywords;
  t

let keyword s =
  let rec find = function (w, k) :: rest -> if String.equal w s then k else find rest | [] -> None in
  if String.length s = 0 then None else find by_first.(Char.code s.[0])

(* And the words that mean something in some places only: it in a short function, as after a use, _ in a pattern and ? after
   a result. *)
let words = List.map fst keywords @ [ "it"; "as"; "_"; "?"; ".."; "!" ]

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
let[@inline] is_name_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_' || c >= '\128'
let[@inline] is_name c = is_name_start c || is_digit c

let is_public name = name <> "" && name.[0] >= 'A' && name.[0] <= 'Z'
let is_plain_name s = s <> "" && is_name_start s.[0] && String.for_all (fun c -> is_name c && c <> '_') s && keyword s = None

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

(* A name from outside as a public Cesia name, for a column of SQL and a key that From reads: created_at gives CreatedAt,
   name Name. A text that is no identifier, as max(score), stays. *)
let public_name s =
  let letter = function 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false in
  if s = "" || not (letter s.[0] && String.for_all (function '0' .. '9' -> true | c -> letter c) s) then s
  else
    match String.concat "" (List.map String.capitalize_ascii (String.split_on_char '_' s)) with
    | "" -> s
    | name -> name

(* The words of a name with a _, joined by capitals, for the hint of its error. *)
let joined ~public name =
  let words = List.filter (fun w -> w <> "") (String.split_on_char '_' name) in
  let cap = String.concat "" (List.map String.capitalize_ascii words) in
  if public then cap else String.uncapitalize_ascii cap

(* The column in code points: a UTF-8 continuation byte doesn't count. *)
let[@inline] pos_at st i =
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

let[@inline] peek_at st k = if st.i + k < String.length st.src then st.src.[st.i + k] else '\000'

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
  let clean () =
    let text = String.sub s start (st.i - start) in
    if String.contains text '_' then String.concat "" (String.split_on_char '_' text) else text
  in
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
    (* A short whole number, as most are: its value as it is read, with no text to convert. *)
    let v = ref 0 and plain = ref ((not !is_float) && st.i - start <= 18) in
    for k = start to st.i - 1 do
      if !plain then if is_digit s.[k] then v := (!v * 10) + Char.code s.[k] - 48 else plain := false
    done;
    if !plain then { t = INT !v; pos = start_pos; sp }
    else
    let text = clean () in
    if !is_float then { t = FLOAT (float_of_string text); pos = start_pos; sp }
    else
      match int_of_string_opt text with
      | Some v -> { t = INT v; pos = start_pos; sp }
      | None -> error st start_pos (Messages.number_too_big text)
  end

let rec scan st ~in_code : token array =
  (* An array that doubles, faster than the dynamic array of the Stdlib: lexing is half of the start of a big program. *)
  let out = ref (Array.make (if in_code then 8 else 1024) { t = EOF; pos = Pos.make 1 1; sp = false }) and count = ref 0 in
  let add tok =
    if !count = Array.length !out then begin
      let bigger = Array.make (2 * !count) tok in
      Array.blit !out 0 bigger 0 !count;
      out := bigger
    end;
    !out.(!count) <- tok;
    incr count
  in
  let s = st.src and n = String.length st.src in
  let sp = ref true in
  let depth = ref 0 in
  let fin = ref false in
  let[@inline] push t pos = add { t; pos; sp = !sp }; sp := false in
  while not !fin do
    if st.i >= n then begin
      if in_code then error st (pos_at st st.i) Messages.text_not_closed;
      fin := true
    end else begin
      let c = s.[st.i] in
      match c with
      | ' ' | '\t' | '\r' ->
        let j = ref (st.i + 1) in
        while !j < n && (match s.[!j] with ' ' | '\t' | '\r' -> true | _ -> false) do incr j done;
        st.i <- !j;
        sp := true
      | '\n' ->
        let pos = pos_at st st.i in
        st.i <- st.i + 1;
        new_line st;
        push NL pos;
        sp := true
      | '-' when peek_at st 1 = '-' ->
        error st (pos_at st st.i) (if peek_at st 2 = '>' then Messages.arrow_outside else Messages.comment_dashes)
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
        add tok;
        sp := false
      | _ when is_name_start c ->
        let start = st.i in
        let pos = pos_at st st.i in
        let j = ref (start + 1) in
        while !j < n && is_name s.[!j] do incr j done;
        st.i <- !j;
        push (word_token st pos (String.sub s start (!j - start))) pos
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
        | '.', '.' -> two DOTDOT
        | ':', _ -> one COLON
        | ';', _ -> one SEMI
        | ',', _ -> one COMMA
        | '.', _ -> one DOT
        | '?', _ -> one QUESTION
        | '!', _ -> one BANG
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
  Array.sub !out 0 !count

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
    | '\\', (('\\' | '"') as c) | '$', ('$' as c) -> two c
    | '"', '"' -> error st (pos_at st st.i) Messages.text_doubled_quote
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
