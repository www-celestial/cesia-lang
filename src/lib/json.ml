open Types

exception Bad of string

let max_depth = 1000

(* The high bit of each byte of a word that is zero, and of no other: the test of Hacker's Delight, 6-1, exact, as in
   Native, here again so that it stays inline in every profile. *)
let lows = 0x7F7F7F7F7F7F7F7FL
let[@inline] zero_bytes t = Int64.lognot (Int64.logor (Int64.logor (Int64.add (Int64.logand t lows) lows) t) lows)

(* Does a word of eight bytes hold one that a text can't keep as it is: a quote, a backslash, or a control character,
   whose three high bits are zero? Texts are read and written eight bytes at a time (SWAR). *)
let[@inline] stops w =
  not (Int64.equal 0L (Int64.logor (zero_bytes (Int64.logand w 0xE0E0E0E0E0E0E0E0L))
                         (Int64.logor (zero_bytes (Int64.logxor w 0x2222222222222222L)) (zero_bytes (Int64.logxor w 0x5C5C5C5C5C5C5C5CL)))))

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
  (* The end of a run of bytes that a text keeps as they are, from j: its closing quote, an escape, a control character
     or the end of the document. *)
  let rec plain j =
    if j + 8 <= n && not (stops (String.get_int64_le s j)) then plain (j + 8)
    else if j < n && (match s.[j] with '"' | '\\' -> false | c -> c >= ' ') then plain (j + 1)
    else j
  in
  let text () =
    incr i;
    let j = plain !i in
    if j < n && s.[j] = '"' then begin
      (* No escape, as in most texts: one copy of the run. *)
      let t = String.sub s !i (j - !i) in
      i := j + 1;
      t
    end else begin
      let b = Buffer.create (max 16 (2 * (j - !i))) in
      Buffer.add_substring b s !i (j - !i);
      i := j;
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
        | _ ->
          let j = plain !i in
          Buffer.add_substring b s !i (j - !i);
          i := j;
          go ()
      in
      go ();
      Buffer.contents b
    end
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

(* The bytes between two that need an escape go as one run. *)
let add_text b s =
  Buffer.add_char b '"';
  let n = String.length s in
  let rec go from k =
    if k + 8 <= n && not (stops (String.get_int64_le s k)) then go from (k + 8)
    else if k >= n then Buffer.add_substring b s from (n - from)
    else
      match s.[k] with
      | ('"' | '\\') as c ->
        Buffer.add_substring b s from (k - from);
        Buffer.add_char b '\\';
        Buffer.add_char b c;
        go (k + 1) (k + 1)
      | c when c < ' ' ->
        Buffer.add_substring b s from (k - from);
        Buffer.add_string b (match c with '\n' -> "\\n" | '\t' -> "\\t" | '\r' -> "\\r" | c -> Printf.sprintf "\\u%04x" (Char.code c));
        go (k + 1) (k + 1)
      | _ -> go from (k + 1)
  in
  go 0 0;
  Buffer.add_char b '"'

let write ctx ~pretty v =
  let b = Buffer.create 64 in
  let line depth = if pretty then begin
      Buffer.add_char b '\n';
      Buffer.add_string b (String.make (2 * depth) ' ')
    end
  in
  (* n items between an opening and a closing character, add k writing the k-th: a loop, no list made. *)
  let group opening closing depth n add =
    Buffer.add_char b opening;
    if n > 0 then begin
      for k = 0 to n - 1 do
        if k > 0 then Buffer.add_char b ',';
        line (depth + 1);
        add k
      done;
      line depth
    end;
    Buffer.add_char b closing
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
    | Array a when Array.length a.dims > 0 ->
      (* Lists in lists, the first index outermost, so that x[i][j][k] of the JSON is a[i, j, k]. *)
      Runtime.pay ctx (a.rows * a.cols);
      let rec nest depth d at stride =
        let below = stride * a.dims.(d) in
        if d = Array.length a.dims - 1 then group '[' ']' depth a.dims.(d) (fun i -> go (depth + 1) (Value.elt a (at + (i * stride))))
        else group '[' ']' depth a.dims.(d) (fun i -> nest (depth + 1) (d + 1) (at + (i * stride)) below)
      in
      if depth + Array.length a.dims > max_depth then bad x;
      nest depth 0 0 1
    | Array a ->
      Runtime.pay ctx (a.rows * a.cols);
      group '[' ']' depth (a.rows * a.cols) (fun k -> go (depth + 1) (Value.elt a k))
    | Struct { shape = { sname = Some _; _ } as shape; fields = s; _ } ->
      let fields = Trie.vals_array s in
      (* Public fields only: a small one, a password hash, never leaks into a response. *)
      Runtime.charge ctx (Array.length fields + 1);
      let public = Array.of_list (List.filter (fun k -> Lexer.is_public shape.names.(k)) (List.init (Array.length fields) Fun.id)) in
      group '{' '}' depth (Array.length public) (fun k -> member depth shape.names.(public.(k)) fields.(public.(k)))
    | Dict _ ->
      let o = Value.items x in
      Runtime.charge ctx ((Array.length o / 2) + 1);
      group '{' '}' depth (Array.length o / 2) (fun k -> member depth (Value.text_of ctx o.(2 * k)) o.((2 * k) + 1))
    | _ -> bad x
  and member depth k v =
    add_text b k;
    Buffer.add_char b ':';
    if pretty then Buffer.add_char b ' ';
    go (depth + 1) v
  in
  go 0 v;
  Text (Buffer.contents b)

let text ctx v = match write ctx ~pretty:false v with Text s -> s | _ -> ""

let natives =
  [ "Parse", Native.nat ~result:true "Parse" 1 1 parse;
    "Text", Native.nat "Text" 1 1 (fun ctx a -> write ctx ~pretty:false a.(0));
    "Pretty", Native.nat "Pretty" 1 1 (fun ctx a -> write ctx ~pretty:true a.(0)) ]
