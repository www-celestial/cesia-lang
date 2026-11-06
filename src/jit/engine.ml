(* The JIT's tier: makes native code of a unit and runs it, for the hooks of [Tier] that the interpreter calls. *)
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
  stride : int;  (* the interpreter's frames for the unit's calls, as [Ir.func]'s; -1 when unknown *)
  need : int;
  mutable bails : int;  (* the runs that a failed guard sent back to the interpreter *)
}

(* What the interpreter holds of it. *)
type Tier.code += Native of code

let native = function Native c -> c | _ -> invalid_arg "Engine: code of another JIT"

(* One io for the process: native code runs to its end without letting another fiber in, and what a run gives is read
   before the checkpoint that may. *)
let io = Array.make Ir.io_size 0

let make (w : world) (ver : version) fns start loops =
  let pure = Array.for_all (fun (f : Ir.func) -> f.pure) fns and calls = Array.exists (fun (f : Ir.func) -> f.calls) fns in
    (* A run that writes arrays can't start again when the stack runs out: such units would have to reserve it all. *)
    if calls && not pure then None
    else begin
      let text, entry = Mirtext.emit fns in
      if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then (prerr_string text; flush stderr);
      match Jit.load text [| entry |] with
      | [| addr |] ->
        let fn = fns.(0) in
        let written = List.filter_map (fun (s, wr, _) -> if wr then Some s else None) (Array.to_list fn.arrays) in
        let known = Array.for_all (fun (f : Ir.func) -> f.stride >= 0) fns in
        let most g = if known then Array.fold_left (fun m f -> max m (g f)) 0 fns else -1 in
        Some { addr; fn; ret = (match ver.ret with TF -> Kfloat | _ -> Kint); pure; calls; written = Array.of_list written;
               reloads = w.reloads; start; loops; stride = most (fun f -> f.stride); need = most (fun f -> f.need); bails = 0 }
      | _ -> None
      | exception Failure m ->
        if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ m);
        None
    end

(* One run from [entry]. The interpreter's view of fuel stays exact: what native code used, nested quanta included,
   comes off [ctx.fuel], so the next checkpoint counts it. *)
let rec run ?(leave = false) (ctx : ctx) code entry =
  let b = ctx.b and w = ctx.w in
  if b + code.fn.size > ctx.cap then Runtime.grow ctx (b + code.fn.size);
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
  (* Under a limit of memory, native frames ask for the stack the interpreter's would: its call puts a frame at most
     [stride] above its caller's, which takes at most [need]; native frames, 2 apart from the first, stop where those would
     pass the stack. *)
  let mem =
    if w.limits.memory_words = max_int || code.stride <= 0 || code.need <= 0 then max_int
    else begin
      let first = b + code.fn.frame + code.fn.hidden and room = ctx.cap - code.need - b - code.stride in
      if room < 0 then first - 1 else first + (2 * (room / code.stride))
    end
  in
  io.(Ir.io_mem) <- mem;
  io.(Ir.io_lim) <- min (min (ctx.cap - 2) depth) mem;
  io.(Ir.io_budget) <- (if w.steps_left = max_int then 1 lsl 60 else w.steps_left - (ctx.refill - fuel0));
  io.(Ir.io_until) <- ctx.until - (ctx.refill - fuel0);
  io.(Ir.io_leave) <- (if leave then 1 else 0);
  (* The constants whose first field native code reads, after the frame, where nothing else is while it runs. *)
  Array.iteri (fun j c -> ctx.v.(b + code.fn.frame + j) <- c) code.fn.consts;
  let st = Jit.call code.addr ctx.i ctx.f ctx.v io in
  if st = Ir.stack_out then begin
    (* Pure: the run wrote nothing that shows, so it starts again on a longer stack. *)
    ctx.fuel <- fuel0;
    Runtime.grow ctx (max (ctx.cap + 1) (min (2 * ctx.cap) (depth + 2)));
    run ~leave ctx code entry
  end else if st = Ir.frames_out then begin
    (* As the interpreter's call: the stacks grow, the frame entered, so that a limit reached names it; then the run starts
       again, as nothing it wrote shows. *)
    ctx.fuel <- fuel0;
    let site = ctx.site in
    ctx.b <- io.(Ir.io_frame);
    ctx.site <- io.(Ir.io_point);
    Runtime.grow ctx (ctx.cap + 1);
    ctx.b <- b;
    ctx.site <- site;
    run ~leave ctx code entry
  end else begin
    ctx.fuel <- fuel0 - (io.(Ir.io_spent) + io.(Ir.io_quantum) - io.(Ir.io_fuel));
    st
  end

(* At least [n] words of the young heap for native code: OCaml's own allocation collects when they are not there, and runs
   what the runtime has pending. *)
let rec room n =
  if n > 0 then begin
    ignore (Sys.opaque_identity (n, n, n, n, n, n, n));
    room (n - 8)
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
  else if code = Ir.err_write then begin
    (* As the interpreter's write: the array owned, so copied when shared, then the write, which fails. *)
    let top = Runtime.own ctx ctx.v.(ctx.b + b) in
    Arrays.write ctx top [| Arrays.At a |] (Float 0.)
  end;
  failwith "jit: an error that the interpreter doesn't see"

(* Runs until native code ends: a checkpoint between quanta, as the interpreter's own, may let other fibers run, as no C
   frame is left. Gives ok, fallback (nothing ran) or returned. *)
(* The point of a region's own loop after its step: where the interpreter can take the loop over. *)
let root_point code = match code.loops with [||] -> -1 | a -> let _, _, _, p = a.(Array.length a - 1) in p

(* Runs until native code ends: a checkpoint between quanta, as the interpreter's own, may let other fibers run, as no C
   frame is left. Gives ok, fallback (nothing ran), returned, or reloaded: a reload came at a checkpoint, so native code,
   made from the old code, stops at its loop's step and the interpreter goes on with the new. Elsewhere in the region,
   native code goes on to that step first; a whole version's native code goes on to its end, and its next call is the
   interpreter's. *)
let go (ctx : ctx) code entry =
  let rec again ?(leave = false) entry first =
    let st = run ~leave ctx code entry in
    if st = Ir.fuel_out then begin
      let p = io.(Ir.io_point) in
      Runtime.checkpoint ctx (ctx.b + code.fn.frame);
      if ctx.w.reloads = code.reloads then again (p + 1) false
      else if p = root_point code then Ir.reloaded
      else again ~leave:(root_point code >= 0) (p + 1) false
    end
    else if st = Ir.gc then begin
      room io.(Ir.io_a);
      again (io.(Ir.io_point) + 1) false
    end
    else if st = Ir.error then fail ctx
    else if st = Ir.too_deep then begin
      ctx.b <- io.(Ir.io_frame);
      Runtime.limit "depth" io.(Ir.io_point)
    end
    else if st = Ir.too_long then begin
      ctx.b <- io.(Ir.io_frame);
      Runtime.limit "steps" ctx.site
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

(* A version hot as a whole: its entries go native when it lowers. [Tier] put back its interpreted entries first. *)
let promote (w : world) (ver : version) =
  let ri = ver.ri and rf = ver.rf in
  match Lower.unit w ver with
  | None -> ()
  (* A body without a loop or a call is as fast interpreted as the way in and out of native code. *)
  | Some fns when not (fns.(0).calls || Array.length fns.(0).resumes > 1) -> ()
  | Some fns when !Tier.watching && Array.length fns.(0).resumes > 1 -> ()
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

(* A loop whose guesses lack a value yet, or whose code was dropped, is tried again, a few times. *)
let max_tries = 8

let compile (ctx : ctx) (l : Tier.loop) ver =
  let w = ctx.w in
  if (not l.failed) && l.code = None then begin
    match Lower.region ~ctx w ver l.expr with
    | Some (fns, start, loops) ->
      (match make w ver fns start loops with
       | Some c ->
         l.code <- Some (Native c);
         l.reloads <- c.reloads
       | None -> l.failed <- true)
    | None -> l.failed <- true
    | exception Lower.Unseen ->
      l.tries <- l.tries + 1;
      if l.tries >= max_tries then l.failed <- true
  end

let live (ctx : ctx) (l : Tier.loop) = match l.code with Some c when l.reloads = ctx.w.reloads -> Some c | _ -> None

(* Native code takes arrays of floats only, and writes only into owned ones: a shared one is copied at its first write,
   which the interpreter does, at its step. Checked before the interpreter leaves its loops, so that native code then never
   falls back; a loop that doesn't fit stays interpreted, and is checked again at its next checkpoint. *)
let fits (ctx : ctx) code =
  Array.for_all
    (fun (slot, written, store) ->
       match ctx.v.(ctx.b + slot) with
       | Array { store = F _; a_owned; _ } when store = 0 -> a_owned || not written
       | Array { store = V _; a_owned; _ } when store = 1 -> a_owned || not written
       | _ -> false)
    (native code).fn.arrays

(* At a hot checkpoint inside [l]: the outermost loop around it, [l] included, that lowers, as one region; [outer] the
   loops around [l], the nearest first. *)
let pick (ctx : ctx) (l : Tier.loop) ver outer =
  let rec go = function
    | [] -> None
    | (c : Tier.loop) :: rest ->
      compile ctx c ver;
      (match live ctx c with
       | Some code when fits ctx code -> Some code
       | k ->
         if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then
           prerr_endline (Printf.sprintf "jit: loop %d %s" c.expr.id (if k = None then "has no code" else "doesn't fit"));
         go rest)
  in
  go (List.rev (l :: outer))

(* A loop that the interpreter leaves: its counter and bound to their slots in the region. *)
let place (ctx : ctx) code (l : Tier.loop) n hi =
  let code = native code in
  (* The hidden slots can be past the interpreter's frame. *)
  if ctx.b + code.fn.size > ctx.cap then Runtime.grow ctx (ctx.b + code.fn.size);
  Array.iter
    (fun (node, cs, hs, _) ->
       if node = l.expr.id && cs >= 0 then begin
         ctx.i.(ctx.b + cs) <- n;
         ctx.i.(ctx.b + hs) <- hi
       end)
    code.loops

let after code from =
  let code = native code in
  let rec find k = if k = Array.length code.loops then invalid_arg "Tier.after" else let n, _, _, p = code.loops.(k) in if n = from then p + 1 else find (k + 1) in
  find 0

let enter (ctx : ctx) (l : Tier.loop) code entry : Tier.ran =
  let code = native code in
  let st = go ctx code entry in
  if st = Ir.ok then Ran
  else if st = Ir.reloaded then Reloaded
  else if st = Ir.returned then
    Returned (match code.ret with Kfloat -> Float (result_float ctx code) | Kint | Kval -> Int io.(Ir.io_int))
  else if st = Ir.bailed then begin
    (* A guess that keeps failing: the code goes, and the loop is lowered again later with what the frame holds then. *)
    code.bails <- code.bails + 1;
    if code.bails > 16 then begin
      l.code <- None;
      l.tries <- l.tries + 1;
      if l.tries >= max_tries then l.failed <- true;
      l.seen <- 0
    end;
    Bailed io.(Ir.io_point)
  end
  else begin
    (* Its arrays are not what native code takes this time, or one it writes is shared: nothing ran, this run is the
       interpreter's, which copies at its first write. *)
    if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline (Printf.sprintf "jit: loop %d fell" l.expr.id);
    Fell
  end

let start code = (native code).start + 1

let counter (ctx : ctx) code (l : Tier.loop) =
  let code = native code in
  let rec find k = if k = Array.length code.loops then invalid_arg "Tier.counter" else let n, cs, _, _ = code.loops.(k) in if n = l.expr.id then ctx.i.(ctx.b + cs) else find (k + 1) in
  find 0

let install () = Tier.jit := Some { promote; compile; pick; place; after; enter; start; counter }
