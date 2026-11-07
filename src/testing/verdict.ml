open Ast

(* A failed test shows each part of its verdict with its value: the loader rewrites the verdict of each isX, so that each part
   goes through #note(k, e), which keeps the value of e for note k and gives it back. *)

type kind = Site of int | Any of int | Part of int | Shown | Hidden | Question of int
type sides = Equal of int * int | Near of int * int * int * int

type note = { test : string; prop : string; owner : int; text : string; kind : kind; mutable sides : sides option }

let binop = function
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/" | Pow -> "^" | Eq -> "==" | Ne -> "!=" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="

let level = function Add | Sub -> 7 | Mul | Div -> 8 | Pow -> 10 | Eq | Ne | Lt | Le | Gt | Ge -> 5

(* The code of an expression, with the parentheses its precedence needs: from 2 for or to 12 for a name. *)
let rec text (e : expr) =
  let at l x = let p, s = text x in if p < l then "(" ^ s ^ ")" else s in
  let all f xs = String.concat ", " (Array.to_list (Array.map f xs)) in
  let show x = snd (text x) in
  match e.e with
  | Lint i -> (if i < 0 then 9 else 12), string_of_int i
  | Lfloat x -> (if x < 0. then 9 else 12), Value.float_text x
  | Lbool b -> 12, string_of_bool b
  | Lmissing -> 12, "missing"
  | Ltext s -> 12, Value.quote s
  | Interp parts -> 12, "\"" ^ String.concat "" (Array.to_list (Array.map (function Lit s -> s | Hole x -> "$(" ^ show x ^ ")") parts)) ^ "\""
  | Var n -> 12, n.text
  | Bin (Pow, a, b) -> 10, at 11 a ^ " ^ " ^ at 9 b
  | Bin (op, a, b) -> let l = level op in l, at (if l = 5 then 6 else l) a ^ " " ^ binop op ^ " " ^ at (l + 1) b
  | Neg a -> 9, "-" ^ at 9 a
  | Not a -> 4, "not " ^ at 4 a
  | And (a, b) -> 3, at 3 a ^ " and " ^ at 4 b
  | Or (a, b) -> 2, at 2 a ^ " or " ^ at 3 b
  | Call { callee; args; _ } ->
    11, at 11 callee ^ "(" ^ all (fun (a : arg) -> (match a.aname with Some n -> n ^ " = " | None -> "") ^ show a.value) args ^ ")"
  | Lambda { params = [| { pname = "it"; _ } |]; body = [| { e = Return { rvalue = Some b; _ }; _ } |]; fname = "<anonymous>"; _ } -> text b
  | Lambda f -> 1, (match f.params with [| p |] -> p.pname | ps -> "(" ^ all (fun (p : param) -> p.pname) ps ^ ")") ^ " -> ..."
  | Range (a, b) -> 6, at 7 a ^ ".." ^ at 7 b
  | In_op (a, b) -> 5, at 6 a ^ " in " ^ at 6 b
  | Array_lit rows -> 12, "[" ^ String.concat "; " (Array.to_list (Array.map (all show) rows)) ^ "]"
  | Comp { cbody; cvar; csrc; cguard } ->
    12, "[" ^ show cbody ^ " for " ^ cvar.text ^ " in " ^ show csrc ^ (match cguard with Some g -> " if " ^ show g | None -> "") ^ "]"
  | Index (a, ixs, _) -> 11, at 11 a ^ "[" ^ all (function All -> ":" | Ix x -> show x) ixs ^ "]"
  | Field (a, n) -> 11, at 11 a ^ "." ^ n
  | Struct_lit { sfields; _ } -> 12, "{" ^ all (fun (n, v) -> n ^ ": " ^ show v) sfields ^ "}"
  | End_index -> 12, "end"
  | Question a -> 11, at 11 a ^ "?"
  | _ -> 12, "..."

let show e = snd (text e)

(* A value written whole in the code: 3, "a", [1, 2], {A: 1}. *)
let rec is_literal (e : expr) =
  match e.e with
  | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ -> true
  | Array_lit rows -> Array.for_all (Array.for_all is_literal) rows
  | Struct_lit { sname = None; sfields } -> Array.for_all (fun (_, v) -> is_literal v) sfields
  | Neg a -> is_literal a
  | _ -> false

let is_test = Testing.is_test

let rewrite (fn : func) =
  let aliases = Array.to_list fn.body |> List.filter_map (fun (e : expr) -> match e.e with Use { upath; ualias } -> Some (ualias, upath) | _ -> None) in
  let is_alias (e : expr) = match e.e with Var { text; _ } -> List.mem_assoc text aliases | _ -> false in
  (* pkg.Name, where pkg is the alias of a use of std/pkg. *)
  let names upath name (e : expr) =
    match e.e with
    | Field ({ e = Var { text = a; _ }; _ }, n) -> String.equal n name && List.assoc_opt a aliases = Some upath
    | _ -> false
  in
  let for_all (e : expr) = match e.e with Call { callee; _ } -> names "std/test" "ForAll" callee | _ -> false in
  (* A snapshot shows its own text when it fails. *)
  let snapshot (e : expr) = match e.e with Call { callee; _ } -> names "std/test" "Snapshot" callee | _ -> false in
  let notes = Vec.create () in
  let next = ref 0 in
  let fresh pos e = let id = !next in incr next; { id; pos; e } in
  let add test prop owner e kind =
    Vec.add_last notes { test; prop; owner; text = show e; kind; sides = None };
    Vec.length notes - 1
  in
  (* e becomes #note(k, e), in place. Gives the node that now holds what e held. *)
  let wrap k (e : expr) =
    let inner = fresh e.pos e.e in
    let arg value = { aname = None; value } in
    e.e <- Call { callee = fresh e.pos (Var { text = "#note"; b = Unresolved }); args = [| arg (fresh e.pos (Lint k)); arg inner |]; self_tail = false };
    inner
  in
  let noted test prop owner kind e = let k = add test prop owner e kind in ignore (wrap k e); k in
  (* Each call, field, index and variable inside, once: never a literal, a callee, a use, or what runs more than once. *)
  let rec inside test prop owner (e : expr) =
    match e.e with
    | Lint _ | Lfloat _ | Lbool _ | Lmissing | Ltext _ | End_index | Lambda _ | Fn_def _ | Comp _ | If _ | Match _ | While _
    | For _ -> ()
    | _ when is_alias e || for_all e -> ()
    | Field (a, _) when is_alias a -> ()
    | Var _ | Field _ | Index _ | Call _ | Question _ -> under test prop owner (wrap (add test prop owner e Shown) e)
    | _ -> Resolve.children (inside test prop owner) e
  (* The insides of a value already noted. A name before a dot stays as it is: Rect.Square is a static method of Rect. *)
  and under test prop owner (e : expr) =
    let deeper = inside test prop owner in
    let before (a : expr) = match a.e with Var _ -> () | _ -> deeper a in
    match e.e with
    | Var _ -> ()
    | Field (a, _) -> before a
    | Index (a, ixs, _) -> deeper a; Array.iter (function Ix x -> deeper x | All -> ()) ixs
    | Call { callee; args; _ } ->
      (match callee.e with Field (a, _) -> before a | _ -> ());
      Array.iter (fun (a : arg) -> deeper a.value) args
    | Question a -> under test prop owner a
    | _ -> Resolve.children deeper e
  (* A side of a comparison: noted even as a literal, for the hints, which is then never shown. *)
  and side test prop owner (e : expr) =
    if is_literal e then noted test prop owner Hidden e
    else begin
      let k = add test prop owner e Shown in
      under test prop owner (wrap k e);
      k
    end
  and part test prop owner (e : expr) =
    let note = Vec.get notes owner in
    let two (args : arg array) = match List.filter (fun (a : arg) -> a.aname = None) (Array.to_list args) with [ a; b ] -> Some (a.value, b.value) | _ -> None in
    match e.e with
    | Bin ((Eq | Ne | Lt | Le | Gt | Ge) as op, a, b) ->
      let ka = side test prop owner a in
      let kb = side test prop owner b in
      if op = Eq then note.sides <- Some (Equal (ka, kb))
    | In_op (a, b) -> inside test prop owner a; inside test prop owner b
    | Call { callee; args; _ } when names "std/value" "Equal" callee && two args <> None ->
      let a, b = Option.get (two args) in
      let ka = side test prop owner a in
      note.sides <- Some (Equal (ka, side test prop owner b))
    | Call { callee; args; _ } when names "std/math" "Near" callee && two args <> None ->
      let a, b = Option.get (two args) in
      let ka = side test prop owner a in
      let kb = side test prop owner b in
      let tol n = match Array.find_opt (fun (x : arg) -> x.aname = Some n) args with Some x -> noted test prop owner Hidden x.value | None -> -1 in
      let kr = tol "rel" in
      note.sides <- Some (Near (ka, kb, kr, tol "abs"))
    | _ when for_all e || snapshot e -> ()
    | Var _ -> ()
    | Field _ | Call _ -> under test prop owner e
    | _ -> inside test prop owner e
  (* The value that the test gives, from its last expression, as its return does. *)
  and verdict test prop (e : expr) =
    match e.e with
    | If (_, a, b) -> Array.iter (fun blk -> if Array.length blk > 0 then verdict test prop blk.(Array.length blk - 1)) [| a; b |]
    | Assign _ | While _ | For _ | Fn_def _ | Use _ | Set _ | Destructure _ | Break | Return _ | Hook _ | Interface _ | Lambda _ -> ()
    | _ ->
      let rec flat is (x : expr) = match is x.e with Some (a, b) -> flat is a @ flat is b | None -> [ x ] in
      let parts =
        match e.e with
        | And _ -> flat (function And (a, b) -> Some (a, b) | _ -> None) e
        | Or _ -> flat (function Or (a, b) -> Some (a, b) | _ -> None) e
        | Not a -> [ a ]
        | Call { callee; args = [| { aname = None; value = { e = Array_lit [| row |]; _ } } |]; _ } when names "std/list" "All" callee -> Array.to_list row
        | _ -> []
      in
      let n = List.length parts in
      let k = add test prop (-1) e (match e.e with Or _ -> Any n | _ -> Site n) in
      let inner = wrap k e in
      if parts = [] then part test prop k inner
      else List.iteri (fun i p -> let kp = add test prop k p (Part (i + 1)) in part test prop kp (wrap kp p)) parts
  (* Each return, without entering nested functions. *)
  and returns test prop (e : expr) =
    match e.e with
    | Lambda _ | Fn_def _ -> ()
    | Return { rvalue = Some v; _ } -> verdict test prop v
    | _ -> Resolve.children (returns test prop) e
  (* Each ? and each property of ForAll, once the verdicts have their texts. *)
  and questions test (e : expr) =
    match e.e with
    | Lambda _ | Fn_def _ -> ()
    | Call { args; _ } when for_all e && Array.length args > 0 ->
      Array.iteri (fun i (a : arg) -> if i = 0 then property test a.value else questions test a.value) args
    | Question a ->
      questions test a;
      ignore (noted test "" (-1) (Question (Pos.line e.pos)) a)
    | _ -> Resolve.children (questions test) e
  and block test prop (b : expr array) =
    Array.iter (returns test prop) b;
    if Array.length b > 0 then verdict test prop b.(Array.length b - 1);
    Array.iter (questions test) b
  and property test (e : expr) =
    match e.e with
    | Lambda f ->
      next := max !next f.nnodes;
      block test (match f.params with [| p |] -> p.pname | _ -> "") f.body;
      e.e <- Lambda { f with nnodes = !next }
    | _ -> questions test e
  in
  Array.iter
    (fun (e : expr) ->
       match e.e with
       | Fn_def (n, f) when is_test n.text && Array.length f.params = 0 ->
         next := f.nnodes;
         block n.text "" f.body;
         e.e <- Fn_def (n, { f with nnodes = !next })
       | _ -> ())
    fn.body;
  Vec.to_array notes

let cut s =
  let s = if String.contains s '\n' then String.concat "\\n" (String.split_on_char '\n' s) else s in
  if String.length s <= 160 then s
  else
    let k = ref 157 in
    while !k > 0 && Char.code s.[!k] land 0xC0 = 0x80 do decr k done;
    String.sub s 0 !k ^ "..."

(* The first character where two texts differ, and what follows it in each, cut. *)
let texts a b =
  let n = min (String.length a) (String.length b) in
  let k = ref 0 in
  while !k < n && a.[!k] = b.[!k] do incr k done;
  while !k > 0 && !k < String.length a && Char.code a.[!k] land 0xC0 = 0x80 do decr k done;
  let chars = ref 1 in
  String.iteri (fun i c -> if i < !k && Char.code c land 0xC0 <> 0x80 then incr chars) a;
  let rest s = let r = String.sub s !k (String.length s - !k) in Value.quote (if String.length r > 30 then String.sub r 0 30 ^ "..." else r) in
  Printf.sprintf "character %d: %s vs %s" !chars (rest a) (rest b)

let explain ctx (notes : note array) (got : (Types.t * int) option array) ~test ~prop ~floor result =
  let ran k = k >= 0 && match got.(k) with Some (_, r) -> r >= floor | None -> false in
  let value k = match got.(k) with Some (v, _) -> v | None -> Types.Undef in
  let stamp k = match got.(k) with Some (_, s) -> s | None -> -1 in
  let show v = cut (Value.show ctx v) in
  let latest pick =
    let best = ref (-1) in
    Array.iteri (fun k n -> if n.test = test && ran k && pick n && (!best < 0 || stamp k > stamp !best) then best := k) notes;
    if !best < 0 then None else Some !best
  in
  let is_err = function Types.Struct { shape = { sname = Some "Err"; _ }; _ } -> true | _ -> false in
  let question = if is_err result then latest (fun n -> match n.kind with Question _ -> true | _ -> false) else None in
  match question, latest (fun n -> (n.prop <> "") = prop && match n.kind with Site _ | Any _ -> true | _ -> false) with
  | Some q, _ when is_err (value q) ->
    let line = match notes.(q).kind with Question l -> l | _ -> 0 in
    Some (Messages.test_question line, [ "  " ^ notes.(q).text ^ "?"; "  | " ^ notes.(q).text ^ " = " ^ show (value q) ])
  | _, None -> None
  | _, Some site ->
    let parts = List.filter (fun k -> notes.(k).owner = site && ran k && match notes.(k).kind with Part _ -> true | _ -> false) (List.init (Array.length notes) Fun.id) in
    let failing = List.find_opt (fun k -> value k != Types.True) parts in
    let focus, header =
      match notes.(site).kind, failing with
      | Site n, Some k when n > 1 -> [ k ], Messages.test_part (match notes.(k).kind with Part i -> i | _ -> 0) n
      | Site 1, _ when parts <> [] -> parts, ""
      | Any _, _ -> parts, ""
      | _ -> [ site ], ""
    in
    let seen = Hashtbl.create 8 in
    let values f =
      List.filter_map
        (fun k ->
           let n = notes.(k) in
           if n.owner = f && n.kind = Shown && ran k && not (Hashtbl.mem seen n.text) then begin
             Hashtbl.replace seen n.text ();
             Some ("  | " ^ n.text ^ " = " ^ show (value k))
           end
           else None)
        (List.init (Array.length notes) Fun.id)
    in
    let hints f =
      let is_float = function Types.Float _ -> true | _ -> false in
      match notes.(f).sides with
      | Some (Equal (a, b)) when ran a && ran b ->
        let x = value a and y = value b in
        if (is_float x || is_float y) && Near.first ctx ~tol:{ rel = 1e-9; abs = 0. } x y = None then
          [ "  | " ^ Messages.test_last_bits notes.(a).text notes.(b).text ]
        else begin
          match x, y, Near.first ctx x y with
          | Text p, Text q, Some ("", _, _) -> [ "  | first difference: " ^ texts p q ]
          | Array p, Array q, Some ("", _, _) ->
            let list (a : Types.arr) = a.rows = 1 && Array.length a.dims = 0 in
            let size (a : Types.arr) =
              if list a then string_of_int a.cols else String.concat "x" (Array.to_list (Array.map string_of_int (Arrays.sizes a))) in
            [ Printf.sprintf "  | first difference: %s %s vs %s" (if list p && list q then "length" else "size") (size p) (size q) ]
          | _, _, Some (path, p, q) when path <> "" -> [ Printf.sprintf "  | first difference: %s: %s vs %s" path (show p) (show q) ]
          | _ -> []
        end
      | Some (Near (a, b, r, t)) when ran a && ran b ->
        let tol = Near.tol_of ctx (if ran r then value r else Undef) (if ran t then value t else Undef) in
        (match Near.first ctx ~tol (value a) (value b) with
         | Some (path, p, q) ->
           let at = if path = "" then "" else path ^ ": " in
           (match p, q with
            | (Int _ | Float _), (Int _ | Float _) ->
              let num = function Types.Int i -> float_of_int i | Float x -> x | _ -> 0. in
              let x = num p and y = num q in
              let allowed = Float.max (tol.rel *. Float.max (Float.abs x) (Float.abs y)) tol.abs in
              let zero = (x = 0. || y = 0.) && tol.abs = 0. in
              [ Printf.sprintf "  | first beyond tolerance: %s%s vs %s, off by %s, allowed %s" at (show p) (show q)
                  (Value.float_text (Float.abs (x -. y))) (Value.float_text allowed) ]
              @ if zero then [ "  | " ^ Messages.test_rel_zero ] else []
            | _ -> [ Printf.sprintf "  | first difference: %s%s vs %s" at (show p) (show q) ])
         | None -> [])
      | _ -> []
    in
    let bools =
      match result with
      | Types.Array a when a.rows * a.cols > 0
                         && List.for_all (fun k -> match Value.elt a k with True | False -> true | _ -> false) (List.init (a.rows * a.cols) Fun.id) ->
        [ "  | " ^ Messages.test_bools ]
      | _ -> []
    in
    let lines =
      match notes.(site).kind with
      | Site 1 -> ("  " ^ notes.(site).text) :: List.concat_map values focus
      | _ -> List.concat_map (fun f -> ("  " ^ notes.(f).text) :: values f) focus
    in
    let extra = List.concat_map (fun f -> if value f == Types.False then hints f else []) focus @ bools in
    let room = max 1 (8 - List.length extra) in
    Some (header, List.filteri (fun i _ -> i < room) lines @ extra)

let property (notes : note array) (got : (Types.t * int) option array) ~test =
  let best = ref None in
  Array.iteri
    (fun k n ->
       match got.(k), n.kind, !best with
       | Some (_, r), (Site _ | Any _), _ when n.test = test && n.prop <> "" && (match !best with Some (_, b) -> r > b | None -> true) ->
         best := Some (n.prop, r)
       | _ -> ())
    notes;
  Option.map fst !best
