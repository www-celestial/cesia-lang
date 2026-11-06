open Types

type code = ..

let off = 0
let hot = 1
let always = 2
let mode = ref hot

(* Under --watch, where reloads come: a version with loops leaves them to regions, which hand over to the interpreter at a
   reload; a version's native code as a whole would go on with the old code to its end. *)
let watching = ref false

(* A version runs natively after this many calls; a loop after this many checkpoints inside it. *)
let calls_before = 1000
let checkpoints_before = 2

type loop = { mutable seen : int; mutable code : code option; mutable reloads : int; mutable failed : bool; expr : Ast.expr }

let loop (e : Ast.expr) = { seen = 0; code = None; reloads = 0; failed = false; expr = e }

exception Handoff of code * int

type ran = Ran | Fell | Returned of t | Reloaded

type jit = {
  promote : world -> version -> unit;
  compile : world -> loop -> version -> unit;
  pick : ctx -> loop -> version -> loop list -> code option;
  place : ctx -> code -> loop -> int -> int -> unit;
  after : code -> int -> int;
  enter : ctx -> loop -> code -> int -> ran;
  start : code -> int;
  counter : ctx -> code -> loop -> int;
}

let jit : jit option ref = ref None
let loader = ref ignore
let available = ref false
let tried = ref false

(* The JIT, loaded at the first unit that gets hot, once: missing or refused, everything stays interpreted. *)
let loaded () =
  if Option.is_none !jit && not !tried then begin
    tried := true;
    !loader ()
  end;
  !jit

(* Only native code, which the JIT made, leads here. *)
let the () = match !jit with Some j -> j | None -> invalid_arg "Tier: no JIT"

let on () = !mode <> off && !available

let watch (w : world) (ver : version) =
  if on () && (ver.ret == TI || ver.ret == TF) && not w.hooks then begin
    let ri = ver.ri and rf = ver.rf and rv = ver.rv in
    let promote () =
      ver.ri <- ri;
      ver.rf <- rf;
      ver.rv <- rv;
      match loaded () with Some j -> j.promote w ver | None -> ()
    in
    let calls = ref 0 in
    let due () =
      incr calls;
      if !calls >= (if !mode = always then 1 else calls_before) then (promote (); true) else false
    in
    ver.ri <- (fun ctx -> if due () then ver.ri ctx else ri ctx);
    ver.rf <- (fun ctx -> if due () then ver.rf ctx else rf ctx);
    ver.rv <- (fun ctx -> if due () then ver.rv ctx else rv ctx)
  end

let live (ctx : ctx) l = match l.code with Some _ as c when l.reloads = ctx.w.reloads -> c | _ -> None

let ready (ctx : ctx) l ver =
  if !mode = always && l.seen = 0 then begin
    l.seen <- 1;
    match loaded () with Some j -> j.compile ctx.w l ver | None -> ()
  end;
  live ctx l

let hot (ctx : ctx) l ver outer =
  l.seen <- l.seen + 1;
  if l.seen < checkpoints_before then None
  else match loaded () with Some j -> j.pick ctx l ver outer | None -> None

let id l = l.expr.id
let place ctx code l n hi = (the ()).place ctx code l n hi
let is_root code l = match l.code with Some c -> c == code | None -> false
let after code from = (the ()).after code from
let enter ctx l code entry = (the ()).enter ctx l code entry
let start code = (the ()).start code
let counter ctx code l = (the ()).counter ctx code l
