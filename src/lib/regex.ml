open Types

exception Bad of string

type node =
  | Empty
  | Set of bool * (int * int) list
  | Any
  | Seq of node list
  | Alt of node * node
  | Repeat of node * int * int option * bool
  | Group of int * node
  | Bol
  | Eol
  | Word of bool

type inst =
  | Char of bool * (int * int) list
  | Dot
  | Split of int * int
  | Jump of int
  | Save of int
  | At_start
  | At_end
  | At_word of bool
  | Match

(* [cost] bounds the work of a thread at one position: the search pays it per byte. *)
type regex = { prog : inst array; groups : int; icase : bool; lines : bool; dotall : bool; cost : int }

let max_count = 1000
let max_nesting = 100
let max_program = 50_000
let max_groups = 1000
let max_class = 1000
let digit = [ 48, 57 ]
let word = [ 48, 57; 65, 90; 95, 95; 97, 122 ]
let space = [ 9, 13; 32, 32 ]

let parse pattern =
  let cs =
    let out = ref [] and i = ref 0 in
    while !i < String.length pattern do
      let d = String.get_utf_8_uchar pattern !i in
      out := Uchar.to_int (Uchar.utf_decode_uchar d) :: !out;
      i := !i + max 1 (Uchar.utf_decode_length d)
    done;
    Array.of_list (List.rev !out)
  in
  let n = Array.length cs and i = ref 0 and groups = ref 0 in
  let icase = ref false and lines = ref false and dotall = ref false in
  let peek () = if !i < n then cs.(!i) else -1 in
  let is c = peek () = Char.code c in
  let next () = incr i in
  let bad text = raise (Bad text) in
  let number () =
    let start = !i and v = ref 0 in
    while peek () >= 48 && peek () <= 57 && !v <= max_count do
      v := (!v * 10) + peek () - 48;
      next ()
    done;
    if !i = start then bad "a count needs a number";
    if !v > max_count then bad "a count is too large";
    !v
  in
  (* An escape: a set, or a single character. *)
  let escape () =
    next ();
    if !i >= n then bad "a backslash ends the pattern";
    let c = peek () in
    next ();
    match Char.chr (c land 0x7F), c < 128 with
    | 'd', true -> Set (false, digit)
    | 'D', true -> Set (true, digit)
    | 'w', true -> Set (false, word)
    | 'W', true -> Set (true, word)
    | 's', true -> Set (false, space)
    | 'S', true -> Set (true, space)
    | 'n', true -> Set (false, [ 10, 10 ])
    | 't', true -> Set (false, [ 9, 9 ])
    | 'r', true -> Set (false, [ 13, 13 ])
    | _ -> Set (false, [ c, c ])
  in
  let member_of_class () =
    if is '\\' then begin
      match escape () with
      | Set (false, ranges) -> ranges
      | _ -> bad "a class can't hold a negated escape"
    end else begin
      if !i >= n then bad "a class isn't closed";
      let c = peek () in
      next ();
      [ c, c ]
    end
  in
  let char_class () =
    next ();
    let negated = is '^' in
    if negated then next ();
    let ranges = ref [] and first = ref true in
    while !first || not (is ']') do
      first := false;
      if !i >= n then bad "a class isn't closed";
      (match member_of_class () with
       | [ (a, _) ] when is '-' && !i + 1 < n && cs.(!i + 1) <> Char.code ']' ->
         next ();
         (match member_of_class () with
          | [ (b, _) ] when b >= a -> ranges := (a, b) :: !ranges
          | _ -> bad "a range is backwards")
       | members -> ranges := members @ !ranges)
    done;
    next ();
    if List.length !ranges > max_class then bad "a class is too large";
    Set (negated, !ranges)
  in
  let rec alternatives depth =
    if depth > max_nesting then bad "the pattern is nested too deeply";
    let left = sequence depth in
    if is '|' then begin
      next ();
      Alt (left, alternatives depth)
    end else left
  and sequence depth =
    let items = ref [] in
    while !i < n && not (is '|') && not (is ')') do
      items := quantified depth :: !items
    done;
    Seq (List.rev !items)
  and quantified depth =
    let item = ref (atom depth) in
    let again = ref true in
    while !again do
      let bounds =
        if is '*' then (next (); Some (0, None))
        else if is '+' then (next (); Some (1, None))
        else if is '?' then (next (); Some (0, Some 1))
        else if is '{' then begin
          next ();
          let low = number () in
          let high =
            if is ',' then begin
              next ();
              if is '}' then None else Some (number ())
            end else Some low
          in
          if not (is '}') then bad "a count isn't closed";
          next ();
          (match high with Some h when h < low -> bad "a count is backwards" | _ -> ());
          Some (low, high)
        end else None
      in
      match bounds with
      | None -> again := false
      | Some (low, high) ->
        let lazy_ = is '?' in
        if lazy_ then next ();
        item := Repeat (!item, low, high, not lazy_)
    done;
    !item
  and atom depth =
    if is '(' then group depth
    else if is ')' then bad "a parenthesis isn't open"
    else if is '[' then char_class ()
    else if is '.' then (next (); Any)
    else if is '^' then (next (); Bol)
    else if is '$' then (next (); Eol)
    else if is '*' || is '+' || is '?' || is '{' then bad "nothing to repeat"
    else if is '\\' then begin
      if !i + 1 < n && cs.(!i + 1) = Char.code 'b' then (i := !i + 2; Word true)
      else if !i + 1 < n && cs.(!i + 1) = Char.code 'B' then (i := !i + 2; Word false)
      else escape ()
    end else begin
      let c = peek () in
      next ();
      Set (false, [ c, c ])
    end
  and group depth =
    next ();
    let closed x =
      if not (is ')') then bad "a parenthesis isn't closed";
      next ();
      x
    in
    if is '?' then begin
      next ();
      if is ':' then begin
        next ();
        closed (alternatives (depth + 1))
      end else begin
        while is 'i' || is 'm' || is 's' do
          (if is 'i' then icase := true else if is 'm' then lines := true else dotall := true);
          next ()
        done;
        closed Empty
      end
    end else begin
      incr groups;
      if !groups > max_groups then bad "the pattern has too many groups";
      let k = !groups in
      closed (Group (k, alternatives (depth + 1)))
    end
  in
  let tree = alternatives 0 in
  if !i < n then bad "a parenthesis isn't open";
  tree, !groups, !icase, !lines, !dotall

let compile tree groups icase lines dotall =
  let code = ref (Array.make 64 Match) and len = ref 0 in
  let push x =
    if !len >= max_program then raise (Bad "the pattern is too large");
    if !len = Array.length !code then code := Array.append !code (Array.make !len Match);
    !code.(!len) <- x;
    incr len;
    !len - 1
  in
  let set at x = !code.(at) <- x in
  let choice greedy a b = if greedy then Split (a, b) else Split (b, a) in
  (* A repeated item that emits nothing would never reach the size of the program. *)
  let visits = ref 0 in
  let rec emit node =
    incr visits;
    if !visits > 4 * max_program then raise (Bad "the pattern is too large");
    match node with
    | Empty -> ()
    | Set (negated, ranges) -> ignore (push (Char (negated, ranges)))
    | Any -> ignore (push Dot)
    | Seq items -> List.iter emit items
    | Alt (a, b) ->
      let split = push (Split (0, 0)) in
      emit a;
      let jump = push (Jump 0) in
      set split (Split (split + 1, !len));
      emit b;
      set jump (Jump !len)
    | Group (k, x) ->
      ignore (push (Save (2 * k)));
      emit x;
      ignore (push (Save ((2 * k) + 1)))
    | Bol -> ignore (push At_start)
    | Eol -> ignore (push At_end)
    | Word b -> ignore (push (At_word b))
    | Repeat (x, low, high, greedy) ->
      for _ = 1 to low do
        emit x
      done;
      (match high with
       | None ->
         let split = push (Split (0, 0)) in
         emit x;
         ignore (push (Jump split));
         set split (choice greedy (split + 1) !len)
       | Some high ->
         let splits = ref [] in
         for _ = low + 1 to high do
           splits := push (Split (0, 0)) :: !splits;
           emit x
         done;
         List.iter (fun at -> set at (choice greedy (at + 1) !len)) !splits)
  in
  emit (Group (0, tree));
  ignore (push Match);
  let prog = Array.sub !code 0 !len in
  let weight = function Char (_, ranges) -> 1 + List.length ranges | Save _ -> groups + 2 | _ -> 1 in
  { prog; groups; icase; lines; dotall; cost = Array.fold_left (fun total i -> total + weight i) 0 prog }

let in_ranges c ranges = List.exists (fun (a, b) -> c >= a && c <= b) ranges

let matches re negated ranges c =
  let swapped = if c >= 65 && c <= 90 then c + 32 else if c >= 97 && c <= 122 then c - 32 else c in
  (in_ranges c ranges || (re.icase && in_ranges swapped ranges)) <> negated

let decode s pos =
  let d = String.get_utf_8_uchar s pos in
  Uchar.to_int (Uchar.utf_decode_uchar d), max 1 (Uchar.utf_decode_length d)

let is_word_byte s pos = pos >= 0 && pos < String.length s && in_ranges (Char.code s.[pos]) word

type threads = { pcs : int array; caps : int array array; mutable count : int }

(* The leftmost match from [from]: the positions of its groups, or None. *)
let exec ctx re s from =
  let size = Array.length re.prog and n = String.length s in
  let marks = Array.make size (-1) and generation = ref 0 in
  let current = ref { pcs = Array.make size 0; caps = Array.make size [||]; count = 0 } in
  let upcoming = ref { pcs = Array.make size 0; caps = Array.make size [||]; count = 0 } in
  let rec add list pc caps pos =
    if marks.(pc) <> !generation then begin
      marks.(pc) <- !generation;
      match re.prog.(pc) with
      | Jump target -> add list target caps pos
      | Split (a, b) ->
        add list a caps pos;
        add list b caps pos
      | Save k ->
        let caps = Array.copy caps in
        caps.(k) <- pos;
        add list (pc + 1) caps pos
      | At_start -> if pos = 0 || (re.lines && s.[pos - 1] = '\n') then add list (pc + 1) caps pos
      | At_end -> if pos = n || (re.lines && s.[pos] = '\n') then add list (pc + 1) caps pos
      | At_word expected ->
        if is_word_byte s (pos - 1) <> is_word_byte s pos = expected then add list (pc + 1) caps pos
      | Char _ | Dot | Match ->
        list.pcs.(list.count) <- pc;
        list.caps.(list.count) <- caps;
        list.count <- list.count + 1
    end
  in
  let start = Array.make (2 * (re.groups + 1)) (-1) in
  let found = ref None and pos = ref from and running = ref true and unpaid = ref 0 in
  while !running do
    if !unpaid >= 256 then begin
      Runtime.pay ctx (!unpaid * re.cost);
      unpaid := 0
    end;
    if Option.is_none !found then add !current 0 start !pos;
    let c, width = if !pos < n then decode s !pos else -1, 1 in
    incr generation;
    let cur = !current and up = !upcoming in
    up.count <- 0;
    let k = ref 0 in
    while !k < cur.count do
      let pc = cur.pcs.(!k) and caps = cur.caps.(!k) in
      (match re.prog.(pc) with
       | Char (negated, ranges) -> if c >= 0 && matches re negated ranges c then add up (pc + 1) caps (!pos + width)
       | Dot -> if c >= 0 && (re.dotall || c <> 10) then add up (pc + 1) caps (!pos + width)
       | Match ->
         found := Some caps;
         k := cur.count
       | _ -> ());
      incr k
    done;
    current := up;
    upcoming := cur;
    unpaid := !unpaid + width;
    if !pos >= n || (up.count = 0 && Option.is_some !found) then running := false else pos := !pos + width
  done;
  Runtime.pay ctx (!unpaid * re.cost);
  !found

let points = Native.points_between

let group s (caps : int array) k =
  if caps.((2 * k)) < 0 || caps.((2 * k) + 1) < 0 then Missing
  else Text (String.sub s caps.(2 * k) (caps.((2 * k) + 1) - caps.(2 * k)))

(* [before] is the number of code points before the match. *)
let result ctx s re caps before =
  let shape = Value.shape_of ctx.w [| "Text"; "Start"; "Stop"; "Groups" |] in
  let names = Array.init re.groups (fun k -> group s caps (k + 1)) in
  let groups = Arrays.list names in
  let start = before + 1 in
  let stop = start + points s caps.(0) caps.(1) - 1 in
  Struct { shape; fields = [| group s caps 0; Int start; Int stop; groups |]; r_owned = true }

(* Every match from the start of the text, the empty ones included. *)
let all_matches ctx re s =
  let n = String.length s in
  let rec go from acc =
    if from > n then List.rev acc
    else
      match exec ctx re s from with
      | None -> List.rev acc
      | Some caps ->
        let next = if caps.(1) > caps.(0) then caps.(1) else if caps.(1) < n then caps.(1) + snd (decode s caps.(1)) else n + 1 in
        go next (caps :: acc)
  in
  go 0 []

let template s by caps groups =
  let b = Buffer.create 32 and i = ref 0 and n = String.length by in
  while !i < n do
    let c = by.[!i] in
    if c = '$' && !i + 1 < n && by.[!i + 1] = '$' then begin
      Buffer.add_char b '$';
      i := !i + 2
    end else if c = '$' && !i + 1 < n && by.[!i + 1] >= '0' && by.[!i + 1] <= '9' then begin
      let k = Char.code by.[!i + 1] - 48 in
      if k <= groups then begin
        match group s caps k with
        | Text t -> Buffer.add_string b t
        | _ -> ()
      end;
      i := !i + 2
    end else begin
      Buffer.add_char b c;
      incr i
    end
  done;
  Buffer.contents b

let natives () =
  let cache = Hashtbl.create 16 in
  let compiled ctx pattern =
    match Hashtbl.find_opt cache pattern with
    | Some re -> re
    | None ->
      if String.contains pattern '\000' then Runtime.fail ctx Type (Messages.regex_bad "it holds a zero byte");
      let re =
        try
          let tree, groups, icase, lines, dotall = parse pattern in
          compile tree groups icase lines dotall
        with Bad text -> Runtime.fail ctx Type (Messages.regex_bad text)
      in
      if Hashtbl.length cache >= 1000 then Hashtbl.reset cache;
      Hashtbl.replace cache pattern re;
      re
  in
  let args ctx name (a : t array) k =
    let re = compiled ctx (Native.text_arg ctx name a.(0)) and s = Native.text_arg ctx name a.(k) in
    re, s
  in
  [ "Test", Native.nat "Test" 2 2 (fun ctx a ->
        let re, s = args ctx "Test" a 1 in
        Value.of_bool (Option.is_some (exec ctx re s 0)));
    "Find", Native.nat "Find" 2 2 (fun ctx a ->
        let re, s = args ctx "Find" a 1 in
        match exec ctx re s 0 with
        | Some caps -> result ctx s re caps (points s 0 caps.(0))
        | None -> Missing);
    "FindAll", Native.nat "FindAll" 2 2 (fun ctx a ->
        let re, s = args ctx "FindAll" a 1 in
        let last = ref 0 and seen = ref 0 in
        let shown (caps : int array) =
          seen := !seen + points s !last caps.(0);
          last := caps.(0);
          result ctx s re caps !seen
        in
        Arrays.list (Array.of_list (List.map shown (all_matches ctx re s))));
    "Replace", Native.nat "Replace" 3 3 (fun ctx a ->
        let re, s = args ctx "Replace" a 2 in
        let by = Native.text_arg ctx "Replace" a.(1) in
        let b = Buffer.create (String.length s) and last = ref 0 in
        List.iter
          (fun (caps : int array) ->
             let piece = template s by caps re.groups in
             Runtime.reserve ctx (((caps.(0) - !last + String.length piece) / 8) + 1);
             Buffer.add_string b (String.sub s !last (caps.(0) - !last));
             Buffer.add_string b piece;
             last := caps.(1))
          (all_matches ctx re s);
        Buffer.add_string b (String.sub s !last (String.length s - !last));
        Text (Buffer.contents b));
    "Split", Native.nat "Split" 2 2 (fun ctx a ->
        let re, s = args ctx "Split" a 1 in
        let pieces = ref [] and last = ref 0 in
        List.iter
          (fun (caps : int array) ->
             if caps.(1) > caps.(0) then begin
               pieces := Text (String.sub s !last (caps.(0) - !last)) :: !pieces;
               last := caps.(1)
             end)
          (all_matches ctx re s);
        Arrays.list (Array.of_list (List.rev (Text (String.sub s !last (String.length s - !last)) :: !pieces)))) ]
