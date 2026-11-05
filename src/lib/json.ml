open Types

exception Bad of string

let max_depth = 1000

let parse_text ctx s =
  let n = String.length s and i = ref 0 in
  (* A value as deep as the limit of values could not be shown, or even compared. *)
  let max_depth = min max_depth (ctx.w.limits.nesting / 2) in
  let peek () = if !i < n then s.[!i] else '\000' in
  let bad text = raise (Bad (Messages.json_at text (!i + 1))) in
  let spaces () =
    while !i < n && (match s.[!i] with ' ' | '\n' | '\r' | '\t' -> true | _ -> false) do
      incr i
    done
  in
  let word w v =
    let m = String.length w in
    if !i + m <= n && String.equal (String.sub s !i m) w then begin
      i := !i + m;
      v
    end else bad Messages.json_unexpected
  in
  let hex4 () =
    if !i + 4 > n then bad Messages.json_short_escape;
    match int_of_string_opt ("0x" ^ String.sub s !i 4) with
    | Some c when String.for_all (function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false) (String.sub s !i 4) ->
      i := !i + 4;
      c
    | _ -> bad Messages.json_hex_escape
  in
  let unicode b =
    let c = hex4 () in
    let code =
      if c >= 0xD800 && c <= 0xDBFF then begin
        if not (!i + 2 <= n && s.[!i] = '\\' && s.[!i + 1] = 'u') then bad Messages.json_surrogate;
        i := !i + 2;
        let low = hex4 () in
        if low < 0xDC00 || low > 0xDFFF then bad Messages.json_surrogate;
        0x10000 + ((c - 0xD800) lsl 10) + (low - 0xDC00)
      end
      else if c >= 0xDC00 && c <= 0xDFFF then bad Messages.json_surrogate
      else c
    in
    Buffer.add_utf_8_uchar b (Uchar.of_int code)
  in
  let text () =
    incr i;
    let b = Buffer.create 16 in
    let rec go () =
      if !i >= n then bad Messages.json_open_text;
      match s.[!i] with
      | '"' -> incr i
      | '\\' ->
        incr i;
        let c = peek () in
        incr i;
        (match c with
         | '"' | '\\' | '/' -> Buffer.add_char b c
         | 'n' -> Buffer.add_char b '\n'
         | 't' -> Buffer.add_char b '\t'
         | 'r' -> Buffer.add_char b '\r'
         | 'b' -> Buffer.add_char b '\b'
         | 'f' -> Buffer.add_char b '\012'
         | 'u' -> unicode b
         | _ -> bad Messages.json_bad_escape);
        go ()
      | c when c < ' ' -> bad Messages.json_control
      | c ->
        Buffer.add_char b c;
        incr i;
        go ()
    in
    go ();
    Buffer.contents b
  in
  let digits () =
    let start = !i in
    while peek () >= '0' && peek () <= '9' do
      incr i
    done;
    if !i = start then bad Messages.json_digits
  in
  let number () =
    let start = !i in
    if peek () = '-' then incr i;
    if peek () = '0' then incr i else digits ();
    let whole = ref true in
    if peek () = '.' then begin
      whole := false;
      incr i;
      digits ()
    end;
    if peek () = 'e' || peek () = 'E' then begin
      whole := false;
      incr i;
      if peek () = '+' || peek () = '-' then incr i;
      digits ()
    end;
    let t = String.sub s start (!i - start) in
    match if !whole then int_of_string_opt t else None with
    | Some v -> Int v
    | None ->
      let x = float_of_string t in
      if Float.abs x = infinity then bad Messages.json_large;
      Float x
  in
  (* Rows of one document often have the same keys: they share them, as the maps of one literal do. *)
  let last = ref Trie.no_keys in
  let rec value depth =
    if depth > max_depth then bad Messages.json_deep;
    spaces ();
    match peek () with
    | '{' -> obj depth
    | '[' -> arr depth
    | '"' -> Text (text ())
    | 't' -> word "true" True
    | 'f' -> word "false" False
    | 'n' -> word "null" Missing
    | '-' | '0' .. '9' -> number ()
    | _ -> bad Messages.json_no_value
  and arr depth =
    incr i;
    spaces ();
    if peek () = ']' then begin
      incr i;
      Arrays.list [||]
    end else begin
      let rec go acc =
        let acc = value (depth + 1) :: acc in
        spaces ();
        match peek () with
        | ',' -> incr i; go acc
        | ']' -> incr i; acc
        | _ -> bad Messages.json_no_comma_array
      in
      let items = Array.of_list (List.rev (go [])) in
      Runtime.build ctx (Array.length items);
      Arrays.list items
    end
  and obj depth =
    incr i;
    spaces ();
    if peek () = '}' then begin
      incr i;
      Dict.empty ()
    end else begin
      let rec go items =
        spaces ();
        if peek () <> '"' then bad Messages.json_key;
        let key = text () in
        spaces ();
        if peek () <> ':' then bad Messages.json_colon;
        incr i;
        let items = value (depth + 1) :: Text key :: items in
        spaces ();
        match peek () with
        | ',' -> incr i; go items
        | '}' -> incr i; items
        | _ -> bad Messages.json_no_comma_object
      in
      let m = Trie.of_items ~like:!last (Array.of_list (List.rev (go []))) in
      (match Trie.keys_of_map m with k when k != Trie.no_keys -> last := k | _ -> ());
      m
    end
  in
  let v = value 0 in
  spaces ();
  if !i < n then bad Messages.json_after;
  v

let parse ctx (a : t array) =
  let s = Native.text_arg ctx "Parse" a.(0) in
  Runtime.pay_bytes ctx (String.length s);
  match parse_text ctx s with
  | v -> Value.ok ctx.w v
  | exception Bad text -> Value.failure ctx.w "json" text

let add_text b s =
  Buffer.add_char b '"';
  String.iter
    (fun c ->
       match c with
       | '"' -> Buffer.add_string b "\\\""
       | '\\' -> Buffer.add_string b "\\\\"
       | '\n' -> Buffer.add_string b "\\n"
       | '\t' -> Buffer.add_string b "\\t"
       | '\r' -> Buffer.add_string b "\\r"
       | c when c < ' ' -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
       | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"'

let write ctx ~pretty v =
  let b = Buffer.create 256 in
  let line depth = if pretty then begin
      Buffer.add_char b '\n';
      Buffer.add_string b (String.make (2 * depth) ' ')
    end
  in
  let group opening closing depth items add =
    if items = [] then begin
      Buffer.add_char b opening;
      Buffer.add_char b closing
    end else begin
      Buffer.add_char b opening;
      List.iteri
        (fun k item ->
           if k > 0 then Buffer.add_char b ',';
           line (depth + 1);
           add item)
        items;
      line depth;
      Buffer.add_char b closing
    end
  in
  let bad x = Runtime.fail ctx Type (Messages.json_value (Value.describe x)) in
  let rec go depth x =
    if depth > max_depth then bad x;
    match x with
    | Missing -> Buffer.add_string b "null"
    | True -> Buffer.add_string b "true"
    | False -> Buffer.add_string b "false"
    | Int i -> Buffer.add_string b (string_of_int i)
    | Float f ->
      if Float.is_nan f || Float.abs f = infinity then bad x;
      Buffer.add_string b (Value.float_text f)
    | Text s -> add_text b s
    | Array a ->
      Runtime.pay ctx (a.rows * a.cols);
      group '[' ']' depth (List.init (a.rows * a.cols) (Value.elt a)) (go (depth + 1))
    | Struct { shape = { sname = Some _; _ } as shape; fields; _ } ->
      (* Public fields only: a small one, a password hash, never leaks into a response. *)
      Runtime.charge ctx (Array.length fields + 1);
      let public = List.filter (fun k -> Lexer.is_public shape.names.(k)) (List.init (Array.length fields) Fun.id) in
      group '{' '}' depth (List.map (fun k -> shape.names.(k), fields.(k)) public) (member depth)
    | Dict _ ->
      let o = Value.items x in
      Runtime.charge ctx ((Array.length o / 2) + 1);
      group '{' '}' depth (List.init (Array.length o / 2) (fun k -> Value.text_of ctx o.(2 * k), o.((2 * k) + 1))) (member depth)
    | _ -> bad x
  and member depth (k, v) =
    add_text b k;
    Buffer.add_char b ':';
    if pretty then Buffer.add_char b ' ';
    go (depth + 1) v
  in
  go 0 v;
  Text (Buffer.contents b)

let natives =
  [ "Parse", Native.nat "Parse" 1 1 parse;
    "Text", Native.nat "Text" 1 1 (fun ctx a -> write ctx ~pretty:false a.(0));
    "Pretty", Native.nat "Pretty" 1 1 (fun ctx a -> write ctx ~pretty:true a.(0)) ]
