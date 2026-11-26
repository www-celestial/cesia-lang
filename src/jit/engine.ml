(* The JIT's tier: makes native code of a unit and runs it, for the hooks of [Tier] that the interpreter calls. *)
open Types

(* Where a unit's code stands. Level 1 of MIR first, made in half the time; level 2, made from the same text by another
   domain once the unit ran about as long as its level 1 took to make, then replaces it at a safe point. *)
type tier =
  | Level1 of { text : string; entry : string; hot_at : int; mutable steps : int }
      (* the steps its runs took, until [hot_at] *)
  | Making  (* level 2 being made: the unit is [pending]'s *)
  | Final  (* level 2, or level 1 for good when level 2 couldn't be made *)

type code = {
  mutable addr : nativeint;
  mutable mir : nativeint;  (* the context of MIR that holds the code at [addr] *)
  mutable tier : tier;
  fn : Ir.func;  (* the unit's first function, whose frame is the interpreter's *)
  vers : version array;  (* the version of each function of the unit *)
  plain : bool;  (* nothing kept as a number, a map's values or a small array, no variable of a module: none to check *)
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
  mutable colds : int;  (* the runs that ended for the interpreter to make a statement left to it *)
  mutable spent : int;  (* the steps of all its runs *)
  mutable rooms : int;
      (* the calls of a version as a whole that the interpreter made, its nested frames short of room twice *)
  worth : int;  (* the steps of native code that take about as long as making it: once its runs took them, it paid *)
  cells : (int * int * t) array;  (* the variables of modules that any function of the unit took as constants *)
  points : int array;  (* the sites a limit of steps names, as [Mirtext.text]'s: at a tick that leaves *)
  ticks : int array array;  (* at one that stops *)
  entries : (int, int) Hashtbl.t;  (* the site a limit of depth names, by the site of the call, as [Mirtext.text]'s *)
  last : t array;  (* the values of [fn.moving] that the last run took *)
  natives : native array;  (* the natives its code calls through OCaml, by number: [Ir.Native] *)
}

(* What the interpreter holds of it. *)
type Tier.code += Native of code

let native = function Native c -> c | _ -> invalid_arg "Engine: code of another JIT"

(* One io for the process: native code runs to its end without letting another fiber in, and what a run gives is read
   before the checkpoint that may. *)
let io = Array.make Ir.io_size 0

(* A run of a unit that calls natives, while it lasts: its context, its code, its base, the fuel the interpreter gave it
   and the highest base the limit of depth allows. A native may call back into Cesia, whose runs of machine code come
   first then: the last first. While one lasts, no code is freed, as machine code is on the stack. *)
type run = { rctx : ctx; rcode : code; rb : int; mutable fuel0 : int; depth : int; mutable calling : bool }

let runs : run list ref = ref []

(* The calls of natives from machine code in progress: each holds machine code's frames and the C glue's on the
   machine's stack, whose size is the system's (8 MB on Linux, 1 MB on Windows). Past [most_nested], what a native calls
   back runs in the interpreter, whose frames are OCaml's, on a stack that grows. *)
let nested = ref 0
let most_nested = 64

(* The result of the last native that machine code called, which the C glue reads; the exception the last one raised,
   with the base of the frame it was raised in, which [fail] raises again. *)
let result = ref Missing
let raised : (exn * int) option ref = ref None

(* The steps of native code that take about as long as MIR takes to make one line of MIR text at level 1: 1,000 to
   1,400 for ode.Solve's step and the sparse product, 240 for optimize.Root. A unit gets its level 2 once its runs took
   that many steps a line of its text; 2,000 and 4,000 were slower or even on the benchmarks (the docs give both). *)
let steps_per_line = 1000

(* The unit whose level 2 is being made, or made and not taken yet; held here, so that it lives until it takes it. *)
let pending : (code * Level2.state Atomic.t) option ref = ref None

(* The level 2 made takes over from level 1, which is freed. Called before a run of any unit's machine code, where none
   runs anywhere, as machine code never calls back into OCaml and a program runs on one domain: a fiber stopped between
   two quanta of the unit holds its record, not its address. Level 2, made from the same text, has the same frame and
   the same points where a run starts again, so it goes on from there. *)
let settle () =
  match !pending with
  (* A native that machine code called runs: that code is on the stack. *)
  | Some _ when !runs <> [] -> ()
  | None -> ()
  | Some (code, job) ->
    (match Atomic.get job with
     | Level2.Working -> ()
     | Made a ->
       pending := None;
       Jit.free code.mir;
       code.addr <- a.(1);
       code.mir <- a.(0);
       code.tier <- Final;
       if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline "jit: level 2"
     | Refused ->
       pending := None;
       code.tier <- Final)

(* A unit hot at level 1 starts its level 2, or tries again at its next run while another unit's is made. *)
let rise code text entry =
  settle ();
  match Level2.start ~wait:(!Tier.mode = Tier.always) text entry with
  | Some job ->
    code.tier <- Making;
    pending := Some (code, job)
  | None -> ()

(* A unit that nothing holds any more, [pending] included, so that nothing can run its code: its context goes. *)
let release code = Jit.free code.mir

(* A bug of the JIT: any exception but the program's own, an error, a limit or a quit, or memory gone.
   The unit is then not made, and its loop or function stays interpreted: a bug of the JIT never ends a program. *)
let bug = function
  | Value.Kerr _ | Value.Limit _ | Value.Quit _ | Out_of_memory -> false
  | e ->
    if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ Printexc.to_string e);
    true

(* The words of the young heap that a unit whose nested frames allocate wants free where its outermost frame checks room:
   an eighth of the young heap as it is when the unit is made, 2^21 words from the interpreter's first checkpoint on, so
   that a collection always makes that room. *)
let margin () = (Gc.get ()).minor_heap_size / 8

(* Does a function reserve room, which a nested frame can't leave for. *)
let reserves (f : Ir.func) =
  Array.exists (fun (b : Ir.block) -> List.exists (function Ir.Reserve (n, _) -> !n > 0 | _ -> false) b.ins) f.blocks

(* Does a function check room after a call, which stops a frame or a version as a whole. *)
let rooms (f : Ir.func) =
  Array.exists (fun (b : Ir.block) -> List.exists (function Ir.Recheck (n, k) -> !n > 0 && k < 0 | _ -> false) b.ins) f.blocks

let make (w : world) (ver : version) fns start loops =
  let pure = Array.for_all (fun (f : Ir.func) -> f.pure) fns and calls = Array.exists (fun (f : Ir.func) -> f.calls) fns in
  (* A nested frame short of room stops the run: a region's call then bails, and the interpreter makes its statement; a
     version as a whole goes back to the interpreter, which makes the call from its start, so its own frame must write
     nothing that shows and come back to its body at no point but its start. *)
  let nested_room = Array.exists reserves (Array.sub fns 1 (Array.length fns - 1)) || Array.exists rooms fns in
    (* A run that writes arrays can't start again when the stack runs out: its calls must bail then. Those of nested frames
       come back through a call of the first function. *)
    (* A unit that calls natives never starts again: its stacks grow and its room is made where they lack. *)
    let bridged = fns.(0).natives <> [||] in
    if (not bridged) && calls && (not pure) && fns.(0).loose then None
    else if (not bridged) && nested_room && (if loops = [||] then fns.(0).looped || not pure else fns.(0).loose) then None
    else begin
      (* The room the outermost frame checks at its start and at each turn of its loops covers what nested frames make
         then, up to [margin] words: a run comes back there after a collection rather than short in a nested frame. *)
      if nested_room && not bridged then begin
        let margin = margin () in
        Array.iter (fun (b : Ir.block) -> List.iter (function Ir.Reserve (n, p) when p >= 0 -> n := !n + margin | _ -> ()) b.ins) fns.(0).blocks
      end;
      match
        let { Mirtext.text; entry; points; ticks; entries } = Mirtext.emit fns in
        if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then (prerr_string text; flush stderr);
        (text, entry, points, ticks, entries, Jit.load text [| entry |] 1)
      with
      | text, entry, points, ticks, entries, [| mir; addr |] ->
        let fn = fns.(0) in
        let written = List.filter_map (fun (s, wr, _, _) -> if wr then Some s else None) (Array.to_list fn.arrays) in
        let known = Array.for_all (fun (f : Ir.func) -> f.stride >= 0) fns in
        let most g = if known then Array.fold_left (fun m f -> max m (g f)) 0 fns else -1 in
        let lines = String.fold_left (fun n c -> if c = '\n' then n + 1 else n) 0 text in
        let worth = lines * steps_per_line in
        let hot_at = if !Tier.mode = Tier.always then 0 else worth in
        let code =
          { addr; mir; tier = Level1 { text; entry; hot_at; steps = 0 }; fn; vers = Array.map (fun (f : Ir.func) -> f.ver) fns;
            plain =
              fn.numbers = [||] && fn.sunk = [||] && fn.globals = [||] && fn.vecs = [||] && fn.moving = [||]
              && Array.for_all (fun (f : Ir.func) -> f.cells = [||]) fns;
            ret = (match ver.ret with TF -> Kfloat | TI -> Kint | _ -> Kval);
            pure; calls; written = Array.of_list written; reloads = w.reloads; start; loops; stride = most (fun f -> f.stride);
            need = most (fun f -> f.need); bails = 0; colds = 0; spent = 0; rooms = 0; worth;
            cells = Array.concat (List.map (fun (f : Ir.func) -> f.cells) (Array.to_list fns));
            last = Array.make (Array.length fn.moving) Missing; points; ticks; entries; natives = fn.natives }
        in
        Gc.finalise release code;
        Some code
      | _ -> None
      | exception e when bug e -> None
    end

(* Does each variable of a module that the code took as a constant still hold that number, and each it reads from a slot
   a number of the kind the code takes: in every function of the unit, the ones it calls as the first. *)
let holds now v =
  match now, v with
  | Int a, Int b -> a = b
  | Float a, Float b -> Int64.equal (Int64.bits_of_float a) (Int64.bits_of_float b)
  | _ -> false

let of_kind v kind = match v, kind with Int _, Ir.Kint | Float _, Ir.Kfloat -> true | _ -> false

let cells_hold (w : world) code =
  Array.for_all (fun (m, k, v) -> holds w.modules.(m).cells.(k) v) code.cells
  && Array.for_all (fun (m, k, kind) -> of_kind w.modules.(m).cells.(k) kind) code.fn.moving
  && Array.for_all (fun ((v : Ir.var), m, k) -> of_kind w.modules.(m).cells.(k) v.kind) code.fn.globals

(* The variables taken as constants whose number changed, as a slider's set in place: code made after reads them from
   slots. One the session forgot (Undef) is gone for good, and one of another kind no number. *)
let mark_moved (w : world) code =
  Array.iter
    (fun (m, k, v) ->
       match w.modules.(m).cells.(k) with
       | (Int _ | Float _) as now when not (holds now v) -> Lower.mark w m k
       | _ -> ())
    code.cells

let vec_fits v rows cols = match v with Array { rows = r; cols = c; store = F _; dims = [||]; _ } -> r = rows && c = cols | _ -> false

(* Does the value slot of each variable kept as a number hold one of its kind, of each kept as a small array of floats
   one of its shape, and of each kept as a map's or struct's floats one of those keys or that shape, of floats. One that a
   turn assigns before it reads it may hold anything: no turn reads that. *)
let numbers_fit ?(cells = true) (ctx : ctx) code =
  let fn = code.fn in
  ((not cells) || cells_hold ctx.w code)
  && Array.for_all
    (fun ((v : Ir.var), slot, flag) ->
       flag >= 0 || match ctx.v.(ctx.b + slot), v.kind with Float _, Kfloat | Int _, Kint -> true | _ -> false)
    fn.numbers
  && Array.for_all (fun (_, slot, rows, cols, flag) -> flag >= 0 || vec_fits ctx.v.(ctx.b + slot) rows cols) fn.vecs
  && Array.for_all
    (fun (_, slot, carrier) ->
       match ctx.v.(ctx.b + slot), carrier with
       | Dict { keys; vals = F _; _ }, Dict { keys = k; _ } -> keys == k
       | Struct { shape; fields = F _; _ }, Struct { shape = s; _ } -> shape == s
       | _ -> false)
    fn.sunk

(* A status after which the run wrote its variables back to their slots. *)
let wrote (fn : Ir.func) st = st = Ir.ok || st = Ir.fuel_out || st = Ir.bailed || st = Ir.gc || (st = Ir.error && fn.spills)

(* What a run takes from the frame before it starts: the variables kept as numbers unboxed into their hidden slots, the
   maps kept as their values, the variables of modules in registers, the small arrays in slots. *)
let unboxed (ctx : ctx) code =
  let b = ctx.b and w = ctx.w in
  Array.iter
    (fun ((v : Ir.var), slot, flag) ->
       if flag >= 0 then ctx.i.(b + flag) <- 0;
       match ctx.v.(b + slot), v.kind with
       | Float x, Kfloat -> Float.Array.set ctx.f (b + v.slot) x
       | Int n, Kint -> ctx.i.(b + v.slot) <- n
       | _ -> if v.kind = Kfloat then Float.Array.set ctx.f (b + v.slot) 0. else ctx.i.(b + v.slot) <- 0)
    code.fn.numbers;
  Array.iter
    (fun (parts, slot, _) ->
       match ctx.v.(b + slot) with
       | Dict { vals = F d; _ } | Struct { fields = F d; _ } -> Float.Array.blit d 0 ctx.f (b + parts) (Float.Array.length d)
       | _ -> ())
    code.fn.sunk;
  (* A variable of a module in a register: its number from its cell. A [stale] run whose cell holds another kind now goes
     on with the number of its slot, written back at the last checkpoint. *)
  Array.iter
    (fun ((v : Ir.var), m, k) ->
       match w.modules.(m).cells.(k), v.kind with
       | Float x, Kfloat -> Float.Array.set ctx.f (b + v.slot) x
       | Int n, Kint -> ctx.i.(b + v.slot) <- n
       | _ -> ())
    code.fn.globals;
  (* A small array kept in slots: its cells, or, for one a turn assigns before it reads it, nothing to read yet. *)
  Array.iter
    (fun (first, slot, rows, cols, flag) ->
       if flag >= 0 then ctx.i.(b + flag) <- 0;
       (* A read of the store: none of its cells is written while the run lasts. *)
       match ctx.v.(b + slot) with
       | Array { store = F d; _ } as a when vec_fits a rows cols -> Float.Array.blit d 0 ctx.f (b + first) (rows * cols)
       | _ -> Float.Array.fill ctx.f (b + first) (rows * cols) 0.)
    code.fn.vecs

(* What a run that wrote its variables back gives the frame: each of those, boxed or made again. *)
let boxed (ctx : ctx) code =
  let b = ctx.b and w = ctx.w in
  Array.iter
    (fun ((v : Ir.var), slot, flag) ->
       if flag < 0 || ctx.i.(b + flag) <> 0 then
       ctx.v.(b + slot) <- (if v.kind = Kfloat then Float (Float.Array.get ctx.f (b + v.slot)) else Int ctx.i.(b + v.slot)))
    code.fn.numbers;
  Array.iter
    (fun (parts, slot, carrier) ->
       let floats n = F (Float.Array.sub ctx.f (b + parts) n) in
       ctx.v.(b + slot) <-
         (match carrier with
          | Struct { shape; _ } -> Struct { shape; fields = floats (Array.length shape.names); r_owned = true }
          | Dict { keys; _ } -> Dict { keys; vals = floats (Array.length keys.ks); d_owned = true }
          | v -> v))
    code.fn.sunk;
  Array.iter
    (fun ((v : Ir.var), m, k) ->
       w.modules.(m).cells.(k) <- (if v.kind = Kfloat then Float (Float.Array.get ctx.f (b + v.slot)) else Int ctx.i.(b + v.slot)))
    code.fn.globals;
  Array.iter
    (fun (first, slot, rows, cols, flag) ->
       (* -2: one the loop only reads, still in its slot. *)
       if flag = -1 || (flag >= 0 && ctx.i.(b + flag) <> 0) then
         ctx.v.(b + slot) <- Arrays.of_float rows cols (Float.Array.sub ctx.f (b + first) (rows * cols)))
    code.fn.vecs

let imin (a : int) b = if a < b then a else b

(* At least [n] words of the young heap for native code: OCaml's own allocation collects when they are not there, and runs
   what the runtime has pending. *)
let rec room n =
  if n > 0 then begin
    ignore (Sys.opaque_identity (n, n, n, n, n, n, n));
    room (n - 8)
  end

(* The stack native frames may take: under a limit of memory, they ask for the stack the interpreter's would: its call
   puts a frame at most [stride] above its caller's, which takes at most [need]; native frames, 2 apart from the first,
   stop where those would pass the stack. *)
let limits (ctx : ctx) code b depth =
  let mem =
    if ctx.w.limits.memory_words = max_int || code.stride <= 0 || code.need <= 0 then max_int
    else begin
      let first = b + code.fn.frame + code.fn.hidden and room = ctx.cap - code.need - b - code.stride in
      if room < 0 then first - 1 else first + (2 * (room / code.stride))
    end
  in
  io.(Ir.io_mem) <- mem;
  io.(Ir.io_cap2) <- ctx.cap - 2;
  io.(Ir.io_lim) <- imin (imin (ctx.cap - 2) depth) mem

(* The stacks grown for a frame at [at] that native code is about to enter at [site], past them or past what the
   interpreter's frames would take under a limit of memory, as the interpreter grows them at its call: the frame
   entered, linked to its caller's, so that a limit names it, when the stacks hold it. *)
let grow (ctx : ctx) r at site =
  let caller = if at = r.rb + r.rcode.fn.frame + r.rcode.fn.hidden then r.rb else at - 2 in
  if at + 1 < ctx.cap then begin
    ctx.i.(at) <- caller;
    ctx.i.(at + 1) <- site;
    ctx.b <- at
  end
  else ctx.b <- caller;
  ctx.site <- site;
  Runtime.grow ctx (max (at + 3) (ctx.cap + 1))

(* A call of machine code to OCaml, from the C glue: native [k] of the unit, at [site], from the frame at [at], as the
   interpreter calls it, with [a]; or the stacks grown for a frame at [at] (k -1), or room for [at] words of the young
   heap (k -2). [used]: the steps the run made so far. The interpreter's fuel is then what it would be after them, so
   that the native's steps, and those of what it calls back, are counted as the interpreter counts them, and its
   checkpoints come at the same steps; then the run goes on from what is left, its counts made from there. The
   interpreter's frames that a native calls back go above the frame at [at], as they do above the interpreter's own:
   they may write over the constants and the variables of modules that the outermost frame holds, written again after.
   An exception is caught here, as no exception of OCaml may unwind machine code: [fail] raises it again. *)
let bridge (a : t array) =
  match !runs with
  | [] -> None
  | r :: _ ->
    let ctx = r.rctx and code = r.rcode and fn = r.rcode.fn in
    let k = io.(Ir.io_a) and at = io.(Ir.io_b) and site = io.(Ir.io_point) and used = io.(Ir.io_code) in
    let w = ctx.w and s = ctx.site in
    ctx.fuel <- r.fuel0 - used;
    let ok =
      match
        if k >= 0 then begin
          ctx.b <- at;
          ctx.site <- site;
          r.calling <- true;
          incr nested;
          result := code.natives.(k).run ctx a;
          decr nested;
          r.calling <- false
        end
        else if k = -1 then grow ctx r at site
        else if at > 4096 then Gc.minor ()
        else room at
      with
      | () -> true
      | exception e ->
        if r.calling then decr nested;
        r.calling <- false;
        raised := Some (e, ctx.b);
        false
    in
    let b = r.rb in
    let put k v = if ctx.v.(k) != v then ctx.v.(k) <- v in
    for j = 0 to Array.length fn.consts - 1 do put (b + fn.frame + j) fn.consts.(j) done;
    let moved = Ir.moved_at fn in
    for j = 0 to Array.length code.last - 1 do put (b + moved + j) code.last.(j) done;
    ctx.b <- b;
    ctx.site <- s;
    r.fuel0 <- ctx.fuel + used;
    io.(Ir.io_until) <- used + ctx.until - (ctx.refill - ctx.fuel);
    io.(Ir.io_budget) <- (if w.steps_left = max_int then 1 lsl 60 else used + w.steps_left - (ctx.refill - ctx.fuel));
    limits ctx code b r.depth;
    ctx.fuel <- r.fuel0;
    if ok then Some ctx else None

(* One run from [entry]. The interpreter's view of fuel stays exact: what native code used, nested quanta included,
   comes off [ctx.fuel], so the next checkpoint counts it. The variables kept as numbers are unboxed into their hidden
   slots before, and boxed back after a run that wrote them. A [stale] run goes on after a checkpoint where a variable of
   a module changed out of what the code takes: with the numbers the run started with. A [plain] unit, as most versions
   as a whole are, has none of them, and none to check. *)
let rec run ?(leave = false) ?(stale = false) (ctx : ctx) code entry =
  let b = ctx.b and w = ctx.w in
  if b + code.fn.size > ctx.cap then Runtime.grow ctx (b + code.fn.size);
  if !nested >= most_nested || ((not code.plain) && not (numbers_fit ~cells:(not stale) ctx code)) then Ir.fallback else begin
  if not code.plain then unboxed ctx code;
  io.(Ir.io_code) <- 0;
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
  limits ctx code b depth;
  io.(Ir.io_budget) <- (if w.steps_left = max_int then 1 lsl 60 else w.steps_left - (ctx.refill - fuel0));
  io.(Ir.io_until) <- ctx.until - (ctx.refill - fuel0);
  io.(Ir.io_leave) <- (if leave then 1 else 0);
  (* The constants whose first field native code reads, after the frame, where nothing else is while it runs. *)
  let consts = code.fn.consts in
  for j = 0 to Array.length consts - 1 do ctx.v.(b + code.fn.frame + j) <- consts.(j) done;
  (* The variables of modules read from slots, each of its kind, after them: native code reads them at its entry. *)
  if not code.plain then begin
    let at = Ir.moved_at code.fn in
    Array.iteri
      (fun j (m, k, _) ->
         if not stale then code.last.(j) <- w.modules.(m).cells.(k);
         ctx.v.(b + at + j) <- code.last.(j))
      code.fn.moving
  end;
  let r = if code.natives = [||] then None else (let r = { rctx = ctx; rcode = code; rb = b; fuel0; depth; calling = false } in runs := r :: !runs; Some r) in
  let st = Jit.call code.addr ctx.i ctx.f ctx.v io in
  (* Natives called through OCaml counted their steps in the interpreter's fuel, from which the run went on. *)
  let fuel0 = match r with Some r -> runs := List.tl !runs; r.fuel0 | None -> fuel0 in
  if (not code.plain) && wrote code.fn st then boxed ctx code;
  if st = Ir.stack_out then begin
    (* Pure: the run wrote nothing that shows, so it starts again on a longer stack. *)
    ctx.fuel <- fuel0;
    Runtime.grow ctx (max (ctx.cap + 1) (imin (2 * ctx.cap) (depth + 2)));
    run ~leave ~stale ctx code entry
  end else if st = Ir.room_out then begin
    (* A nested frame short of room: what the run did shows nowhere, its steps are not counted. *)
    ctx.fuel <- fuel0;
    st
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
    run ~leave ~stale ctx code entry
  end else begin
    let spent = io.(Ir.io_spent) + io.(Ir.io_quantum) - io.(Ir.io_fuel) in
    ctx.fuel <- fuel0 - spent;
    code.spent <- code.spent + spent;
    (match code.tier with
     | Level1 l ->
       (* Stops at [hot_at]: no overflow, however long the wait for another unit's level 2. *)
       l.steps <- imin l.hot_at (l.steps + spent);
       if l.steps >= l.hot_at then rise code l.text l.entry
     | Making | Final -> ());
    st
  end
  end

(* An error of native code: the interpreter does the operation again, at the same site and on the same frames, so its
   message and trace are the interpreter's own. *)
let fail (ctx : ctx) (c : code) =
  let b0 = io.(Ir.io_base) in
  ctx.b <- io.(Ir.io_frame);
  ctx.site <- io.(Ir.io_point);
  let a = io.(Ir.io_a) and b = io.(Ir.io_b) and code = io.(Ir.io_code) in
  if code = Ir.err_native then begin
    match !raised with
    | Some (e, at) ->
      raised := None;
      ctx.b <- at;
      raise e
    | None -> ()
  end
  else if code = Ir.err_add then ignore (Arith.add_int ctx a b)
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
  end
  else if code = Ir.err_int || code = Ir.err_float then begin
    (* A native's result that the interpreter's typed code takes as a number, as its to_i or to_f says. *)
    let slot = b0 + Ir.moved_at c.fn - 1 in
    let v = ctx.v.(slot) in
    ctx.v.(slot) <- Missing;
    if code = Ir.err_int then Runtime.fail ctx Type (Messages.want_int "This value" (Value.describe v))
    else Runtime.fail ctx Type (Messages.need_number "This value" (Value.describe v))
  end
  else if code = Ir.err_cond then begin
    (* As the interpreter's test of a condition: the value, from the slot native code put it in. *)
    let slot = b0 + Ir.moved_at c.fn - 1 in
    let v = ctx.v.(slot) in
    ctx.v.(slot) <- Missing;
    Runtime.fail ctx Type (Messages.condition (Value.describe v))
  end
  else if code = Ir.err_vec then begin
    (* A small array kept in slots: one of its shape says the same. *)
    let rows = b and cols = io.(Ir.io_ixs) in
    ignore (Arrays.read1 ctx (Arrays.of_float rows cols (Float.Array.make (rows * cols) 0.)) (Arrays.At a))
  end
  else if code = Ir.err_read_nd || code = Ir.err_write_nd then begin
    let ixs = Array.init a (fun d -> Arrays.At io.(Ir.io_ixs + d)) in
    if code = Ir.err_read_nd then ignore (Arrays.read ctx ctx.v.(ctx.b + b) ixs)
    else Arrays.write ctx (Runtime.own ctx ctx.v.(ctx.b + b)) ixs (Float 0.)
  end;
  failwith "jit: an error that the interpreter doesn't see"

(* The site that a limit of steps names at the tick where native code left (status [st] [Ir.fuel_out], at its point) or
   stopped (at the limit, its number in [io_code]), as the interpreter's tick names it: the step's own. Native code
   writes none of it: found here, on the slow path. Of the k steps a tick counts at once, the one past the limit: with
   [io_spent] steps spent with all k against a budget of [io_budget], the (budget - spent + k)-th from 0. *)
let step_site code st =
  if st = Ir.fuel_out then code.points.(io.(Ir.io_point))
  else begin
    let sites = code.ticks.(io.(Ir.io_code)) in
    let k = Array.length sites in
    sites.(max 0 (min (k - 1) (io.(Ir.io_budget) - io.(Ir.io_spent) + k)))
  end

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
  let rec again ?(leave = false) ?(stale = false) ?(short = false) entry first =
    settle ();
    let st = run ~leave ~stale ctx code entry in
    if st = Ir.fuel_out then begin
      let p = io.(Ir.io_point) in
      Runtime.checkpoint ctx (ctx.b + code.fn.frame) (step_site code st);
      (* Another fiber may have given a variable of a module another value there. One the code reads from a slot, still of
         its kind, is read at the next run, as the interpreter reads it at once. One taken as a constant, or of another
         kind now, is as a reload: the run ends at its loop's step, where the interpreter goes on and the loop's code is
         made again; elsewhere native code goes on with the numbers it started with to where it can leave, as a fiber
         switch waits for nested native frames. *)
      let moved = not (cells_hold ctx.w code) in
      if ctx.w.reloads = code.reloads && not moved then again (p + 1) false
      else if p = root_point code then Ir.reloaded
      else again ~leave:(root_point code >= 0) ~stale:moved (p + 1) false
    end
    else if st = Ir.gc then begin
      if io.(Ir.io_a) > 4096 then Gc.minor () else room io.(Ir.io_a);
      again (io.(Ir.io_point) + 1) false
    end
    else if st = Ir.room_out then begin
      (* A nested frame of a version as a whole was short of room in the young heap: once more on an empty one, unless a
         call of it was short there before; short again, the call goes back to the interpreter, from its start, the only
         point where such a version's run comes back: the frame's own step is the call's, counted before native code. *)
      if not short && code.rooms = 0 then begin
        Gc.minor ();
        again ~short:true entry first
      end else begin
        code.rooms <- code.rooms + 1;
        Lower.starve code.vers.(io.(Ir.io_b));
        if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ code.vers.(io.(Ir.io_b)).owner.pname ^ " short of room, a call made by the interpreter");
        st
      end
    end
    else if st = Ir.error then fail ctx code
    else if st = Ir.too_deep then begin
      ctx.b <- io.(Ir.io_frame);
      Runtime.limit "depth" (Hashtbl.find code.entries io.(Ir.io_point))
    end
    else if st = Ir.too_long then begin
      ctx.b <- io.(Ir.io_frame);
      Runtime.limit "steps" (step_site code st)
    end
    else if st = Ir.fallback && not first then failwith "jit: arrays changed under native code"
    else st
  in
  again entry true

(* A version whose calls the interpreter made this many times, its nested frames short of room, is the interpreter's: its
   runs make more than the young heap holds between two collections. *)
let most_rooms = 4

let result_float (ctx : ctx) code = Float.Array.get ctx.f (ctx.b + code.fn.frame)

let int_entry code ri (ctx : ctx) =
  if ctx.w.reloads <> code.reloads || code.rooms > most_rooms then ri ctx
  else if go ctx code 1 = Ir.ok then io.(Ir.io_int)
  else ri ctx

let float_entry code rf (ctx : ctx) =
  if ctx.w.reloads <> code.reloads || code.rooms > most_rooms then rf ctx
  else if go ctx code 1 = Ir.ok then result_float ctx code
  else rf ctx

(* A value given: in the value slot after the constants, which then lets it go. *)
let value_entry code rv (ctx : ctx) =
  if ctx.w.reloads <> code.reloads || code.rooms > most_rooms then rv ctx
  else if go ctx code 1 = Ir.ok then begin
    let slot = ctx.b + code.fn.frame + Array.length code.fn.consts in
    let v = ctx.v.(slot) in
    ctx.v.(slot) <- Missing;
    v
  end
  else rv ctx

(* A version hot as a whole: its entries go native when it lowers. [Tier] put back its interpreted entries first. *)
let promote (w : world) (ver : version) =
  let ri = ver.ri and rf = ver.rf and rv = ver.rv in
  match Lower.unit w ver with
  | exception e when bug e -> ()
  | None -> if !Lower.why <> "" && Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ ver.owner.pname ^ " interpreted: " ^ !Lower.why)
  (* A body without a loop or a call is as fast interpreted as the way in and out of native code. *)
  | Some fns when not (fns.(0).calls || fns.(0).looped) -> ()
  | Some fns when !Tier.watching && fns.(0).looped -> ()
  | Some fns ->
    (match make w ver fns 0 [||] with
     | None -> ()
     | Some code ->
       if ver.ret == TI then begin
         let ri' = int_entry code ri in
         ver.ri <- ri';
         ver.rv <- (fun ctx -> Int (ri' ctx));
         ver.rf <- (fun ctx -> float_of_int (ri' ctx))
       end else if ver.ret == TF then begin
         let rf' = float_entry code rf in
         ver.rf <- rf';
         ver.rv <- (fun ctx -> Float (rf' ctx))
       end else ver.rv <- value_entry code rv)

(* A loop whose guesses lack a value yet, or whose code was dropped, is tried again, a few times. *)
let max_tries = 8

(* A loop's code dropped: one more try, unless that code ran as long as it took to make, as one does whose function a
   session defined again many times over: a loop gives up for good only after codes that didn't pay for themselves. *)
let dropped (l : Tier.loop) code =
  if code.spent >= code.worth then l.tries <- 0;
  l.tries <- l.tries + 1;
  if l.tries >= max_tries then l.failed <- true

(* A variable of a module that a session forgot, as it does with the names of a cell it runs again, is Undef for good:
   code that took it as a constant can never run again, and its drop is an edit of the session, no sign that the loop's
   code keeps failing. *)
let forgot (w : world) code =
  let gone m k = match w.modules.(m).cells.(k) with Undef -> true | _ -> false in
  Array.exists (fun (m, k, _) -> gone m k) code.cells || Array.exists (fun (m, k, _) -> gone m k) code.fn.moving
  || Array.exists (fun (_, m, k) -> gone m k) code.fn.globals

(* Under CESIA_JIT=always a loop is first lowered at its start, before any step, when its calls through a value have met
   no function yet: a refusal then is no sign, and the loop is lowered once more after its first steps, as one hot by its
   runs is ([Tier.warm]). In the default mode a loop is lowered only after steps, and a refusal is for good. *)
let refused (l : Tier.loop) = if !Tier.mode = Tier.always && l.tries = 0 then l.tries <- 1 else l.failed <- true

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
    | None ->
      if !Lower.why <> "" && Sys.getenv_opt "CESIA_JIT_SHOW" <> None then
        prerr_endline (Printf.sprintf "jit: loop %d interpreted: %s" l.expr.id !Lower.why);
      refused l
    | exception Lower.Unseen ->
      l.tries <- l.tries + 1;
      if l.tries >= max_tries then l.failed <- true
    | exception e when bug e -> l.failed <- true
  end

let live (ctx : ctx) (l : Tier.loop) = match l.code with Some c when l.reloads = ctx.w.reloads -> Some c | _ -> None

(* Native code takes arrays of floats, integers or values only, and writes only into owned ones: a shared one is copied at its first write,
   which the interpreter does, at its step. Checked before the interpreter leaves its loops, so that native code then never
   falls back; a loop that doesn't fit stays interpreted, and is checked again at its next checkpoint. So does one that
   [most_nested] natives called from machine code hold on the machine's stack. *)
let fits (ctx : ctx) code =
  !nested < most_nested
  && numbers_fit ctx (native code)
  && Array.for_all
    (fun (slot, written, store, nd) ->
       let dims d = nd = 0 || Array.length d = (if nd = 2 then 0 else nd) in
       match ctx.v.(ctx.b + slot) with
       | Array { store = F _; a_owned; dims = d; _ } when store = 0 -> (a_owned || not written) && dims d
       | Array { store = V _; a_owned; dims = d; _ } when store = 1 -> (a_owned || not written) && dims d
       | Array { store = I _; a_owned; dims = d; _ } when store = 2 -> (a_owned || not written) && dims d
       | _ -> false)
    (native code).fn.arrays

(* At a hot checkpoint inside [l]: the outermost loop around it, [l] included, that lowers, as one region; [outer] the
   loops around [l], the nearest first. *)
let pick (ctx : ctx) (l : Tier.loop) ver outer =
  let rec go = function
    | [] -> None
    | (c : Tier.loop) :: rest ->
      (* Code made for numbers that a module's variables no longer hold is made again. *)
      (match c.code with
       | Some code when not (cells_hold ctx.w (native code)) ->
         c.code <- None;
         mark_moved ctx.w (native code);
         if not (forgot ctx.w (native code)) then dropped c (native code)
       | _ -> ());
      compile ctx c ver;
      (* A region that left [l] to the interpreter, in a statement it doesn't make, can't take it over. *)
      let holds code = Array.exists (fun (n, _, _, _) -> n = l.expr.id) (native code).loops in
      (match live ctx c with
       | Some code when fits ctx code && holds code -> Some code
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

(* A loop's code goes when it went back for cold statements [cold_runs] times or more, having made fewer than
   [cold_steps] steps for each on average: leaving native code and coming back costs about 450 ns, what native code
   gains on 8 to 20 steps of a loop of floats. Two loops of 10^6 turns whose branch left to the interpreter runs every e
   turns: native code lost to the interpreter up to e = 8 in both, won from e = 24 and 16, and broke even between. *)
let cold_runs = 64
let cold_steps = 12

let enter (ctx : ctx) (l : Tier.loop) code entry : Tier.ran =
  let code = native code in
  let st = go ctx code entry in
  if st = Ir.ok then Ran
  else if st = Ir.reloaded then Reloaded
  else if st = Ir.returned then
    Returned (match code.ret with Kfloat -> Float (result_float ctx code) | Kint | Kval -> Int io.(Ir.io_int))
  else if st = Ir.returned_value then begin
    let slot = ctx.b + code.fn.frame + Array.length code.fn.consts in
    let v = ctx.v.(slot) in
    ctx.v.(slot) <- Missing;
    Returned v
  end
  else if st = Ir.bailed then begin
    (* A guess that keeps failing: the code goes, and the loop is lowered again later with what the frame holds then. A
       write or a statement left to the interpreter is no guess. *)
    let why = io.(Ir.io_code) in
    if why <> Ir.written && why <> Ir.cold_code && why <> Ir.leaving_code then code.bails <- code.bails + 1;
    if why = Ir.cold_code then code.colds <- code.colds + 1;
    (* A statement left to the interpreter as cold that runs at most turns: each of them leaves native code and comes
       back, which costs more than the few steps native code made between. The loop is the interpreter's for good. *)
    if code.colds >= cold_runs && code.spent < code.colds * cold_steps then begin
      l.code <- None;
      l.failed <- true
    end
    else if why = Ir.room_code && (code.rooms <- code.rooms + 1; code.rooms > 1) then begin
      (* A call whose nested frames were short of room twice, past the margin of the loop's turn: the loop is made again,
         that version's calls the interpreter's. *)
      let k = io.(Ir.io_b) in
      if k > 0 then Lower.starve code.vers.(k);
      if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then
        prerr_endline ("jit: " ^ (if k > 0 then code.vers.(k).owner.pname else "a loop's call") ^ " short of room, its loop made again");
      l.code <- None;
      dropped l code;
      l.seen <- 0
    end
    else if code.bails > 16 then begin
      l.code <- None;
      dropped l code;
      l.seen <- 0
    end;
    (* A statement in a branch of an if goes to the interpreter as -2 - its node. *)
    let k = io.(Ir.io_point) and points = code.fn.points in
    Bailed (if k >= 0 && k < Array.length points && points.(k) >= 0 then -2 - points.(k) else k)
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

(* A version's native entries, which the interpreter's calls take, as do those of a loop left to it: the version's own
   calls, recursion, and those of native code go native to native, never by them. Coming into native code and going
   back costs what native code gains on about [Tier.short_steps] steps, as for the runs of a loop ([Tier.ran]): a
   version whose first [Tier.short_runs] native entries made fewer steps on average gets its interpreted entries back,
   its code kept, as one with a loop of 2 turns called from a loop that the interpreter keeps, which ran 3 times slower
   native. After [period] calls, [Tier.short_runs] of them are native again, and counted: counted as calls of the
   interpreter, those of a recursion would count its smallest parts. Long, the native entries stay, for good; short, the
   next try comes after twice as many calls, at most [most_calls]. No code is made again, and a version defined again,
   whose entries forward its calls to the new one, keeps those. *)
type calls = { mutable starts : int; mutable steps : int; mutable wait : int; mutable short : bool }

let most_calls = 1 lsl 16

let judge (w : world) (ver : version) ri rf rv =
  let ni = ver.ri and nf = ver.rf and nv = ver.rv in
  let c = { starts = 0; steps = 0; wait = 0; short = false } in
  let ours = ref nv and final = ref false and period = ref (Tier.short_runs * Tier.short_every) in
  let set i f v =
    ver.ri <- i;
    ver.rf <- f;
    ver.rv <- v;
    ours := v
  in
  let show m = if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ ver.owner.pname ^ m) in
  (* A native entry that ended, from [p], a full checkpoint between counted back, as a loop's run. *)
  let rec ended (ctx : ctx) p =
    if (not !final) && (not c.short) && ver.rv == !ours then begin
      let d = p - Tier.position ctx in
      c.starts <- c.starts + 1;
      c.steps <- c.steps + (if d >= 0 then d else max 0 (d + ctx.w.period));
      if c.starts >= 2 * Tier.short_runs then begin
        c.starts <- c.starts / 2;
        c.steps <- c.steps / 2
      end;
      if c.starts >= Tier.short_runs then
        if c.steps < c.starts * Tier.short_steps then begin
          if !period = Tier.short_runs * Tier.short_every then show " interpreted, its calls are short";
          c.short <- true;
          c.wait <- !period;
          period := min (2 * !period) most_calls;
          set (interpreted ri (fun v -> v.ri)) (interpreted rf (fun v -> v.rf)) (interpreted rv (fun v -> v.rv))
        end
        else if Tier.free w then begin
          final := true;
          set ni nf nv;
          show " native, its calls are long"
        end
    end
  and again () =
    if Tier.free w && ver.rv == !ours then begin
      c.short <- false;
      c.starts <- 0;
      c.steps <- 0;
      set (measured ni) (measured nf) (measured nv)
    end
    else c.wait <- !period
  (* A native entry, counted. *)
  and measured : 'a. (ctx -> 'a) -> ctx -> 'a =
    fun f ->
    let entry ctx =
      let p = Tier.position ctx in
      let x = f ctx in
      ended ctx p;
      x
    in
    entry
  (* An entry of the interpreter, until the next try, which then takes this call: [now] is the entry in its place. *)
  and interpreted : 'a. (ctx -> 'a) -> (version -> ctx -> 'a) -> ctx -> 'a =
    fun f now ->
    let entry ctx =
      c.wait <- c.wait - 1;
      if c.wait > 0 then f ctx
      else begin
        again ();
        now ver ctx
      end
    in
    entry
  in
  set (measured ni) (measured nf) (measured nv)

let install () =
  let promote w (ver : version) =
    let ri = ver.ri and rf = ver.rf and rv = ver.rv in
    promote w ver;
    (* In mode always, native entries from the first call to the last, for tests. *)
    if ver.rv != rv && !Tier.mode <> Tier.always then judge w ver ri rf rv
  in
  Runtime.bridged := (fun ctx -> List.exists (fun r -> r.calling && r.rctx == ctx) !runs);
  Callback.register "cesia_jit_native" bridge;
  Callback.register "cesia_jit_io" io;
  Callback.register "cesia_jit_result" result;
  Tier.jit := Some { promote; compile; pick; place; after; enter; start; counter }
