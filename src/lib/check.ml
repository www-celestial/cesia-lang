open Types
open Ast

(* What is known of a value without running: a kind, missing, a struct built by name, or a result. *)
type found = Kind of string | Absent | Built of int * int * string | Result

(* The function or native that a call names, when it is one of a module: a call through a variable is not known. *)
let target w (e : expr) =
  match e.e with
  | Var { b = Cell { m; k; stable = true }; _ } when m < Array.length w.modules && k < Array.length w.modules.(m).cells ->
    Some (m, k, w.modules.(m).cells.(k))
  | _ -> None

(* The constructor of the struct of std/result that a call builds, if it builds one. *)
let built_result w (c : call) =
  match target w c.callee with
  | Some (_, _, Fun { proto; _ }) ->
    (match proto.func.fname, Resolve.struct_fields proto.func with
     | ("Ok" | "Err"), Some [| (("Value" | "Error"), _) |] -> Some proto.func.fname
     | _ -> None)
  | _ -> None

(* The ways out of a function: each value it can end with, by its last expression or a return, the nested functions left
   out. *)
let ways_out (f : func) =
  let out = ref [] in
  let rec last (b : block) = if Array.length b > 0 then tail b.(Array.length b - 1)
  and tail (e : expr) =
    match e.e with
    | If (_, a, b) -> last a; last b
    | Match { arms; _ } -> Array.iter (fun a -> tail a.abody) arms
    | Return { rvalue = Some v; _ } -> tail v
    | Return _ | For _ | While _ | Assign _ | Set _ | Destructure _ | Fn_def _ | Use _ | Interface _ | Hook _ | Break -> ()
    | _ -> out := e :: !out
  in
  let rec returns (e : expr) =
    (match e.e with Return { rvalue = Some v; _ } -> tail v | _ -> ());
    Resolve.children returns e
  in
  last (Lazy.force f.body);
  Array.iter returns (Lazy.force f.body);
  !out

(* Does a call give a result: a native that says so, or a function whose type ends with !, or one with a way out that is
   Ok(...), Err(...) or a call that gives one. [known] holds what is found of each function, and false while it is looked at. *)
let rec gives w known (c : call) =
  match target w c.callee with
  | Some (_, _, Native n) -> n.gives_result
  | Some (m, k, Fun { proto; _ }) ->
    built_result w c <> None
    || (match Hashtbl.find_opt known (m, k) with
        | Some b -> b
        | None ->
          Hashtbl.replace known (m, k) false;
          let f = proto.func in
          let b =
            match f.ret with
            | Some t -> t.tbang
            | None when Resolve.struct_fields f <> None -> false
            | None -> List.exists (fun (e : expr) -> match e.e with Call c -> gives w known c | _ -> false) (ways_out f)
          in
          Hashtbl.replace known (m, k) b;
          b)
  | _ -> false

let kinds = [ "Int"; "Float"; "Number"; "Bool"; "Text"; "Array"; "Dict"; "Function" ]

(* What a value surely is, when the code says it. *)
let rec found w (e : expr) =
  match e.e with
  | Lint _ -> Some (Kind "Int")
  | Lfloat _ -> Some (Kind "Float")
  | Ltext _ | Interp _ -> Some (Kind "Text")
  | Lbool _ -> Some (Kind "Bool")
  | Lmissing -> Some Absent
  | Array_lit _ | Comp _ -> Some (Kind "Array")
  | Struct_lit { sname = None; _ } -> Some (Kind "Dict")
  | Lambda _ -> Some (Kind "Function")
  | Neg x -> found w x
  | Call c ->
    (match target w c.callee with
     | Some (_, _, Native n) when n.gives_result -> Some Result
     | Some (m, k, Fun { proto; _ }) ->
       (match Resolve.struct_fields proto.func, proto.func.ret with
        | Some _, _ -> Some (Built (m, k, proto.func.fname))
        | None, Some { tbang = true; _ } -> Some Result
        | None, Some { tname; tpkg = None; topt = false; tb = Unresolved; _ } when List.mem tname kinds -> Some (Kind tname)
        | _ -> None)
     | _ -> None)
  | _ -> None

let shown_found = function
  | Kind k -> Messages.article k
  | Absent -> "missing"
  | Built (_, _, name) -> Messages.article name
  | Result -> "a result"

(* Does a value of what was found fit a type: [Some false] only when it surely doesn't. *)
let fits w (t : ptype) found =
  let struct_type = match t.tb with
    | Cell { m; k; _ } when m < Array.length w.modules && k < Array.length w.modules.(m).cells ->
      (match w.modules.(m).cells.(k) with Fun { proto; _ } when Resolve.struct_fields proto.func <> None -> Some (m, k) | _ -> None)
    | _ -> None
  in
  match found, t.tb with
  | Absent, _ -> t.topt
  | _, Unresolved when List.mem t.tname kinds ->
    (match found with
     | Kind k -> k = t.tname || (t.tname = "Number" && (k = "Int" || k = "Float")) || (t.tname = "Float" && k = "Int")
                 || (k = "Number" && (t.tname = "Int" || t.tname = "Float"))
     | _ -> false)
  | Built (m, k, _), _ -> (match struct_type with Some (sm, sk) -> sm = m && sk = k | None -> true)
  | _, _ -> struct_type = None

let type_shown (t : ptype) =
  let name = match t.tpkg with Some alias -> alias ^ "." ^ t.tname | None -> t.tname in
  Messages.article name ^ if t.topt then " or missing" else ""

(* The arguments of a call to a known function, struct or native: their number and names, then the types of literals. *)
let arguments w add (e : expr) (c : call) =
  match target w c.callee with
  | Some (_, _, Fun { proto; env = [||] }) ->
    let f = proto.func in
    (match Infer.bind_args f c.args with
     | Error m -> add e.pos false m
     | Ok slots ->
       Array.iteri
         (fun k slot ->
            match slot, f.params.(k).ptype with
            | Some (v : expr), Some t ->
              (match found w v with
               | Some x when not (fits w t x) ->
                 add v.pos false (Messages.wrong_type f.fname f.params.(k).pname (type_shown t) (shown_found x))
               | _ -> ())
            | _ -> ())
         slots)
  | Some (_, _, Native n) ->
    let placed = ref 0 and bad = ref None in
    Array.iteri
      (fun i (a : arg) ->
         let k = match a.aname with
           | None -> i
           | Some name -> (match Array.find_index (String.equal name) n.params with Some k -> k | None -> bad := Some name; i)
         in
         placed := max !placed (k + 1))
      c.args;
    (match !bad with
     | Some name -> add e.pos false (Messages.unknown_arg n.nname name)
     | None ->
       if !placed < n.min_args || !placed > n.max_args then
         let want = if n.min_args = n.max_args then Printf.sprintf "%d arguments" n.min_args
           else Printf.sprintf "%d to %d arguments" n.min_args n.max_args in
         add e.pos false (Messages.arg_count n.nname want !placed))
  | _ -> ()

(* The name of what a call names, with its package when it is another one: sys.Read. *)
let label w host (c : call) =
  match target w c.callee with
  | Some (m, _, cell) ->
    let md = w.modules.(m) in
    let name = match cell with Native n -> n.nname | Fun { proto; _ } -> proto.func.fname | _ -> "" in
    let package =
      if md.path = "" then Filename.basename md.mname
      else if Filename.basename (Filename.dirname md.path) = "std" then Filename.remove_extension (Filename.basename md.path)
      else Filename.basename (Filename.dirname md.path)
    in
    if md.host = host || String.contains name '.' then name else package ^ "." ^ name
  | None -> ""

(* How a value is used: kept or passed on, used as a plain value, or dropped. *)
type use = Kept | Plain | Dropped

(* Results left unhandled, the arguments of calls, and the types of the values a typed function ends with. *)
let rec walk w add known host (u : use) (e : expr) =
  let go = walk w add known host in
  let block u (b : block) =
    Array.iteri (fun i x -> go (if i = Array.length b - 1 then u else Dropped) x) b
  in
  match e.e with
  | Call c ->
    arguments w add e c;
    if u <> Kept && built_result w c = None && gives w known c then
      add e.pos true ((if u = Plain then Messages.result_plain else Messages.result_dropped) (label w host c));
    go Kept c.callee;
    (* A native wants a plain value, but io.Print, which shows an Ok or an Err as well, and fiber.Send, which passes it on. *)
    let native = match target w c.callee with Some (_, _, Native n) -> n.nname <> "Print" && n.nname <> "Send" | _ -> false in
    Array.iter (fun (a : arg) -> go (if native then Plain else Kept) a.value) c.args
  (* == and != compare whole values: a result to an expected one is no mistake. *)
  | Bin ((Eq | Ne), a, b) -> go Kept a; go Kept b
  | Bin (_, a, b) | And (a, b) | Or (a, b) | Range (a, b) | In_op (a, b) -> go Plain a; go Plain b
  | Neg a | Not a -> go Plain a
  | Field (a, ("Value" | "Error")) -> go Kept a
  | Field (a, _) -> go Plain a
  | Index (b, ixs, _) -> go Plain b; Array.iter (function Ix x -> go Plain x | All -> ()) ixs
  | Interp parts -> Array.iter (function Hole x -> go Plain x | Lit _ -> ()) parts
  | If (c, a, b) -> go Plain c; block u a; block u b
  | While { cond; body; _ } -> go Plain cond; block Dropped body
  | For { iter; fbody; _ } -> go Plain iter; block Dropped fbody
  | Comp { cbody; csrc; cguard; _ } -> go Plain csrc; go Kept cbody; Option.iter (go Plain) cguard
  | Match { subject; arms } ->
    go Kept subject;
    Array.iter (fun a -> Option.iter (go Plain) a.guard; go u a.abody) arms
  | Lambda f | Fn_def (_, f) -> func w add known host f
  | _ -> Resolve.children (go Kept) e

(* A function: its body, whose last value goes out, and its result type. *)
and func w add known host (f : func) =
  Array.iter (fun (p : param) -> Option.iter (walk w add known host Kept) p.default) f.params;
  let body = Lazy.force f.body in
  Array.iteri (fun i x -> walk w add known host (if i = Array.length body - 1 then Kept else Dropped) x) body;
  match f.ret with
  | None -> ()
  | Some t ->
    let errs = ref false in
    List.iter
      (fun (v : expr) ->
         let inner = match v.e with Call c -> (match built_result w c, c.args with Some k, [| a |] -> Some (k, a.value) | _ -> None) | _ -> None in
         let wrong x = add v.pos false (Messages.wrong_result f.fname (if t.tbang then "an Ok of " ^ type_shown t ^ ", or an Err" else type_shown t) x) in
         match inner, t.tbang with
         | Some ("Err", _), _ -> errs := true
         | Some (_, x), true -> (match found w x with Some fx when not (fits w t fx) -> wrong (shown_found fx) | _ -> ())
         | Some _, false -> wrong "an Ok"
         | None, true -> (match found w v with Some (Kind _ | Absent | Built _ as fx) -> wrong (shown_found fx) | _ -> ())
         | None, false -> (match found w v with Some fx when not (fits w t fx) -> wrong (shown_found fx) | _ -> ()))
      (ways_out f);
    let rec question (e : expr) = (match e.e with Question _ -> errs := true | _ -> ()); Resolve.children question e in
    Array.iter question (Lazy.force f.body);
    if !errs && not t.tbang then add t.tpos true (Messages.missing_bang f.fname (match t.tpkg with Some a -> a ^ "." ^ t.tname | None -> t.tname))

let file w ~host (fn : func) add = Array.iter (walk w add (Hashtbl.create 64) host Dropped) (Lazy.force fn.body)
