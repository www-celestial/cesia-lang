open Types

type code = {
  addr : nativeint;
  fn : Ir.func;  (* the unit's first function, whose frame is the interpreter's *)
  ret : Ir.kind;  (* the kind of the version's result *)
  pure : bool;
  calls : bool;
  written : int array;  (* the value slots of the arrays it writes *)
  reloads : int;
  start : int;  (* a loop's resume point at its start *)
  loops : (int * int * int * int) array;  (* each loop inside: its node, its counter's and bound's slots or -1, its point *)
}

let off = 0
let hot = 1
let always = 2
let mode = ref hot

(* A version runs natively after this many calls; a loop after this many checkpoints inside it. *)
let calls_before = 1000
let checkpoints_before = 2

(* One io for the process: native code runs to its end without letting another fiber in, and what a run gives is read
   before the checkpoint that may. *)
let io = Array.make Ir.io_size 0

let make (w : world) (ver : version) fns start loops =
  match !Mirtext.backend with
  | None -> None
  | Some be ->
    let pure = Array.for_all (fun (f : Ir.func) -> f.pure) fns and calls = Array.exists (fun (f : Ir.func) -> f.calls) fns in
    (* A run that writes arrays can't start again when the stack runs out: such units would have to reserve it all. *)
    if calls && not pure then None
    else begin
      let text, entry = Mirtext.emit fns in
      if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_string text;
      match be.load text [| entry |] with
      | [| addr |] ->
        let fn = fns.(0) in
        let written = List.filter_map (fun (s, wr) -> if wr then Some s else None) (Array.to_list fn.arrays) in
        Some { addr; fn; ret = (match ver.ret with TF -> Kfloat | _ -> Kint); pure; calls; written = Array.of_list written;
               reloads = w.reloads; start; loops }
      | _ -> None
      | exception Failure m ->
        if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ m);
        None
    end

(* One run from [entry]. The interpreter's view of fuel stays exact: what native code used, nested quanta included,
   comes off [ctx.fuel], so the next checkpoint counts it. *)
let rec run (ctx : ctx) code entry =
  let b = ctx.b and w = ctx.w in
  if b + code.fn.size > ctx.cap then Runtime.grow ctx (b + code.fn.size);
  Array.iter
    (fun slot -> match ctx.v.(b + slot) with Array a as v when not a.a_owned -> ctx.v.(b + slot) <- Runtime.own ctx v | _ -> ())
    code.written;
  let depth = if code.calls then b + code.fn.frame + code.fn.hidden + (2 * (ctx.max_depth - Runtime.frames ctx - 1)) else max_int in
  let fuel0 = ctx.fuel in
  io.(Ir.io_base) <- b;
  io.(Ir.io_entry) <- entry;
  io.(Ir.io_fuel) <- fuel0;
  io.(Ir.io_quantum) <- fuel0;
  io.(Ir.io_spent) <- 0;
  io.(Ir.io_status) <- Ir.ok;
  io.(Ir.io_cap2) <- ctx.cap - 2;
  io.(Ir.io_depth) <- depth;
  io.(Ir.io_lim) <- min (ctx.cap - 2) depth;
  io.(Ir.io_budget) <- (if w.steps_left = max_int then 1 lsl 60 else w.steps_left - (ctx.refill - fuel0));
  io.(Ir.io_until) <- ctx.until - (ctx.refill - fuel0);
  io.(Ir.io_leave) <- 0;
  let call = match !Mirtext.backend with Some be -> be.call | None -> assert false in
  let st = call code.addr ctx.i ctx.f ctx.v io in
  if st = Ir.stack_out then begin
    (* Pure: the run wrote nothing that shows, so it starts again on a longer stack. *)
    ctx.fuel <- fuel0;
    Runtime.grow ctx (max (ctx.cap + 1) (min (2 * ctx.cap) (depth + 2)));
    run ctx code entry
  end else begin
    ctx.fuel <- fuel0 - (io.(Ir.io_spent) + io.(Ir.io_quantum) - io.(Ir.io_fuel));
    st
  end

(* An error of native code: the interpreter does the operation again, at the same site and on the same frames, so its
   message and trace are the interpreter's own. *)
let fail (ctx : ctx) =
  ctx.b <- io.(Ir.io_frame);
  ctx.site <- io.(Ir.io_point);
  let a = io.(Ir.io_a) and b = io.(Ir.io_b) and code = io.(Ir.io_code) in
  if code = Ir.err_add then ignore (Arith.add_int ctx a b)
  else if code = Ir.err_sub then ignore (Arith.sub_int ctx a b)
  else if code = Ir.err_mul then ignore (Arith.mul_int ctx a b)
  else if code = Ir.err_neg then ignore (Arith.neg ctx (Int a))
  else if code = Ir.err_div then ignore (Arith.int_div ctx a b)
  else if code = Ir.err_mod then ignore (Arith.int_mod ctx a b)
  else if code = Ir.err_read then ignore (Arrays.read1 ctx ctx.v.(ctx.b + b) (Arrays.At a))
  else if code = Ir.err_write then Arrays.write ctx ctx.v.(ctx.b + b) [| Arrays.At a |] (Float 0.);
  failwith "jit: an error that the interpreter doesn't see"

(* Runs until native code ends: a checkpoint between quanta, as the interpreter's own, may let other fibers run, as no C
   frame is left. Gives ok, fallback (nothing ran) or returned. *)
let go (ctx : ctx) code entry =
  let rec again entry first =
    let st = run ctx code entry in
    if st = Ir.fuel_out then begin
      let p = io.(Ir.io_point) in
      Runtime.checkpoint ctx (ctx.b + code.fn.frame);
      again (p + 1) false
    end
    else if st = Ir.error then fail ctx
    else if st = Ir.too_deep then begin
      ctx.b <- io.(Ir.io_frame);
      Runtime.limit "depth" io.(Ir.io_point)
    end
    else if st = Ir.too_long then begin
      ctx.b <- io.(Ir.io_frame);
      Runtime.limit "steps" (-1)
    end
    else if st = Ir.fallback && not first then failwith "jit: arrays changed under native code"
    else st
  in
  again entry true

let result_float (ctx : ctx) code = Float.Array.get ctx.f (ctx.b + code.fn.frame)

let int_entry code ri (ctx : ctx) =
  if ctx.w.reloads <> code.reloads then ri ctx
  else if go ctx code 1 = Ir.ok then io.(Ir.io_int)
  else ri ctx

let float_entry code rf (ctx : ctx) =
  if ctx.w.reloads <> code.reloads then rf ctx
  else if go ctx code 1 = Ir.ok then result_float ctx code
  else rf ctx

let watch (w : world) (ver : version) =
  if !mode <> off && (ver.ret == TI || ver.ret == TF) && (not w.hooks) && !Mirtext.backend <> None then begin
    let ri = ver.ri and rf = ver.rf and rv = ver.rv in
    let promote () =
      ver.ri <- ri;
      ver.rf <- rf;
      ver.rv <- rv;
      match Lower.unit w ver with
      | None -> ()
      (* A body without a loop or a call is as fast interpreted as the way in and out of native code. *)
      | Some fns when not (fns.(0).calls || Array.length fns.(0).resumes > 1) -> ()
      | Some fns ->
        (match make w ver fns 0 [||] with
         | None -> ()
         | Some code ->
           if ver.ret == TI then begin
             let ri' = int_entry code ri in
             ver.ri <- ri';
             ver.rv <- (fun ctx -> Int (ri' ctx));
             ver.rf <- (fun ctx -> float_of_int (ri' ctx))
           end else begin
             let rf' = float_entry code rf in
             ver.rf <- rf';
             ver.rv <- (fun ctx -> Float (rf' ctx))
           end)
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

type loop = { mutable seen : int; mutable code : code option; mutable failed : bool; expr : Ast.expr }

let loop (e : Ast.expr) = { seen = 0; code = None; failed = false; expr = e }
let on () = !mode <> off && !Mirtext.backend <> None

exception Handoff of code * int

let compile (w : world) l ver =
  if (not l.failed) && l.code = None then begin
    match Lower.region w ver l.expr with
    | Some (fns, start, loops) -> (match make w ver fns start loops with Some c -> l.code <- Some c | None -> l.failed <- true)
    | None -> l.failed <- true
  end

let live (ctx : ctx) l = match l.code with Some c when c.reloads = ctx.w.reloads -> Some c | _ -> None

let ready (ctx : ctx) l ver =
  if !mode = always && l.seen = 0 then begin
    l.seen <- 1;
    compile ctx.w l ver
  end;
  live ctx l

(* Native code takes arrays of floats only: checked before the interpreter leaves its loops, so that native code then
   never falls back. *)
let fits (ctx : ctx) code =
  Array.for_all (fun (slot, _) -> match ctx.v.(ctx.b + slot) with Array { store = F _; _ } -> true | _ -> false) code.fn.arrays

(* At a checkpoint inside [l], hot: the outermost loop around it, [l] included, that lowers, as one region; [outer] the
   loops around [l], the nearest first. *)
let hot (ctx : ctx) l ver outer =
  l.seen <- l.seen + 1;
  if l.seen < checkpoints_before then None
  else begin
    let rec pick = function
      | [] -> None
      | c :: rest ->
        compile ctx.w c ver;
        (match live ctx c with Some code when fits ctx code -> Some code | _ -> pick rest)
    in
    pick (List.rev (l :: outer))
  end

let id l = l.expr.id

(* A loop that the interpreter leaves: its counter and bound to their slots in the region. *)
let place (ctx : ctx) code l n hi =
  Array.iter
    (fun (node, cs, hs, _) ->
       if node = l.expr.id && cs >= 0 then begin
         ctx.i.(ctx.b + cs) <- n;
         ctx.i.(ctx.b + hs) <- hi
       end)
    code.loops

let is_root code l = match l.code with Some c -> c == code | None -> false

let after code from =
  let rec find k = if k = Array.length code.loops then invalid_arg "Tier.after" else let n, _, _, p = code.loops.(k) in if n = from then p + 1 else find (k + 1) in
  find 0

type ran = Ran | Fell | Returned of t

let enter (ctx : ctx) l code entry =
  let st = go ctx code entry in
  if st = Ir.ok then Ran
  else if st = Ir.returned then Returned (match code.ret with Kfloat -> Float (result_float ctx code) | Kint -> Int io.(Ir.io_int))
  else begin
    (* Its arrays are not what native code takes: this loop stays interpreted. *)
    l.code <- None;
    l.failed <- true;
    Fell
  end

let start c = c.start + 1
