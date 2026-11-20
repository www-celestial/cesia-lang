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

(* The last runs of a loop, or native entries of a version, counted, and their steps; [short] says that they were too
   short, and [wait] is the runs, or calls, before the next one counted then. *)
type counts = { mutable starts : int; mutable steps : int; mutable short : bool; mutable wait : int }

let counts () = { starts = 0; steps = 0; short = false; wait = 0 }

type loop = {
  mutable seen : int;
  mutable code : code option;
  mutable reloads : int;
  mutable failed : bool;
  mutable tries : int;
  mutable runs : int;
  counts : counts;
  expr : Ast.expr;
}

let loop (e : Ast.expr) = { seen = 0; code = None; reloads = 0; failed = false; tries = 0; runs = 0; counts = counts (); expr = e }

(* Where a fiber stands: the steps before its next full checkpoint. It falls by one at each step, the checkpoints
   between two full ones included, and is [period] again after a full one. *)
let position (ctx : ctx) = ctx.until - ctx.refill + ctx.fuel

(* A loop that has no native code yet, and may get some: the steps of its runs are counted, and for one left to the
   interpreter as its runs are short, one run in [short_every], to see whether they grow. *)
let short_every = 16

let counting l =
  l.code = None
  && ((not l.failed)
      || l.counts.short
         && begin
           let c = l.counts in
           c.wait <- c.wait - 1;
           c.wait <= 0
         end)

(* A run that comes in from the interpreter and goes back costs about 450 ns, what native code gains on 8 to 20 steps,
   as for the statements the JIT leaves cold (src/jit/engine.ml): a loop of k steps in a function called often ran 3
   times slower as native code at k = 2, 1.5 times at 8, broke even at 12 and won from 16. A loop whose last runs made
   fewer than [short_steps] steps on average, over [short_runs] runs or more, as one of 2 or 3 turns, is left to the
   interpreter without being made, which would cost about 2 ms of the program's own time; a loop around it may still
   take it into its region, and it gets its turn again once its runs are long, as when a session solves a larger
   problem with the same function. Each count is halved past twice [short_runs], so that the last runs counted weigh
   most. *)
let short_runs = 64
let short_steps = 12

(* A run, or a call, that ended, from [p], a full checkpoint between counted back: true once enough were counted to
   tell whether they are short. A run past two of them, longer than [period] steps, counts less than it made: it met
   checkpoints, at which a loop gets hot anyway. *)
let counted (ctx : ctx) c p =
  let d = p - position ctx in
  c.starts <- c.starts + 1;
  c.steps <- c.steps + (if d >= 0 then d else max 0 (d + ctx.w.period));
  if c.starts >= 2 * short_runs then begin
    c.starts <- c.starts / 2;
    c.steps <- c.steps / 2
  end;
  c.starts >= short_runs

let too_short c = c.steps < c.starts * short_steps

let ran (ctx : ctx) l p =
  let c = l.counts in
  if counted ctx c p && l.code = None then begin
    let short = too_short c in
    if short <> c.short then begin
      c.short <- short;
      l.failed <- short
    end
  end;
  if c.short then c.wait <- short_every

(* The steps a loop runs over its runs before it gets native code at the end of a first step. *)
let runs_before = 100_000

(* The steps of a loop interpreted before it gets its code that way. *)
let warm_steps = 8

exception Handoff of code * int

type ran = Ran | Fell | Returned of t | Reloaded | Bailed of int

type jit = {
  promote : world -> version -> unit;
  compile : ctx -> loop -> version -> unit;
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

(* Native code runs no hook: with a debugger, it runs only while the program runs without steps. *)
let free (w : world) = (not w.hooks) || (w.debug.mode == Running && not w.debug.stopped)

let show m = if Sys.getenv_opt "CESIA_JIT_SHOW" <> None then prerr_endline ("jit: " ^ m)

(* A version given native entries, which its calls from the interpreter take, as do those of a loop left to it: the
   version's own calls, recursion, and those from native code go native to native, never by these entries. Its first
   [short_runs] native entries are counted: when they made fewer than [short_steps] steps on average, each paid the way
   into native code and out, as a loop's short runs do, for less than it gained, and the version gets its interpreted
   entries back, its code kept. After [period] calls, [short_runs] of them are native again, and counted: as calls of
   the interpreter, those of a recursion would count its smallest parts. Long, the native entries stay, for good; short,
   the next try comes after twice as many calls, at most [most_calls]. No code is made again. *)
let most_calls = 1 lsl 16

let judge (w : world) (ver : version) ri rf rv =
  let ni = ver.ri and nf = ver.rf and nv = ver.rv in
  let c = counts () and ours = ref nv and final = ref false and period = ref (short_runs * short_every) in
  let set i f v =
    ver.ri <- i;
    ver.rf <- f;
    ver.rv <- v;
    ours := v
  in
  (* Never over entries that came since, as a version defined again forwards its calls to the new one. *)
  let rec after ctx p =
    if (not !final) && (not c.short) && counted ctx c p && ver.rv == !ours then
      if too_short c then begin
        if !period = short_runs * short_every then show (ver.owner.pname ^ " interpreted, its calls are short");
        c.short <- true;
        c.wait <- !period;
        period := min (2 * !period) most_calls;
        set si sf sv
      end
      else if free w then begin
        final := true;
        set ni nf nv;
        show (ver.owner.pname ^ " native, its calls are long")
      end
  (* The calls of the interpreter, until the next try. *)
  and si ctx =
    c.wait <- c.wait - 1;
    if c.wait > 0 then ri ctx else (again (); ver.ri ctx)
  and sf ctx =
    c.wait <- c.wait - 1;
    if c.wait > 0 then rf ctx else (again (); ver.rf ctx)
  and sv ctx =
    c.wait <- c.wait - 1;
    if c.wait > 0 then rv ctx else (again (); ver.rv ctx)
  and again () =
    if free w && ver.rv == !ours then begin
      c.short <- false;
      c.starts <- 0;
      c.steps <- 0;
      set ci cf cv
    end
    else c.wait <- !period
  (* The native entries counted. *)
  and ci ctx =
    let p = position ctx in
    let x = ni ctx in
    after ctx p;
    x
  and cf ctx =
    let p = position ctx in
    let x = nf ctx in
    after ctx p;
    x
  and cv ctx =
    let p = position ctx in
    let x = nv ctx in
    after ctx p;
    x
  in
  set ci cf cv

let watch (w : world) (ver : version) =
  if on () && (ver.ret == TI || ver.ret == TF) then begin
    let ri = ver.ri and rf = ver.rf and rv = ver.rv in
    let promote () =
      ver.ri <- ri;
      ver.rf <- rf;
      ver.rv <- rv;
      match loaded () with
      | Some j ->
        j.promote w ver;
        (* In mode [always], native entries from the first call to the last, for tests. *)
        if ver.rv != rv && !mode <> always then judge w ver ri rf rv
      | None -> ()
    in
    let calls = ref 0 in
    let due () =
      incr calls;
      if !calls >= (if !mode = always then 1 else calls_before) && free w then (promote (); true) else false
    in
    ver.ri <- (fun ctx -> if due () then ver.ri ctx else ri ctx);
    ver.rf <- (fun ctx -> if due () then ver.rf ctx else rf ctx);
    ver.rv <- (fun ctx -> if due () then ver.rv ctx else rv ctx)
  end

let live (ctx : ctx) l = match l.code with Some _ as c when l.reloads = ctx.w.reloads -> c | _ -> None

(* In mode [always], a loop is compiled at its first run, and again at its next runs while its guesses lack values. *)
let ready (ctx : ctx) l ver =
  if !mode = always && l.code = None && (not l.failed) && l.seen < 8 && free ctx.w then begin
    l.seen <- l.seen + 1;
    match loaded () with Some j -> j.compile ctx l ver | None -> ()
  end;
  live ctx l

let hot (ctx : ctx) l ver outer =
  l.seen <- l.seen + 1;
  if l.seen < checkpoints_before || not (free ctx.w) then None
  else match loaded () with Some j -> j.pick ctx l ver outer | None -> None

let warm l n =
  if l.code <> None || l.failed || not (on ()) then false
  else if !mode = always then true
  else begin
    l.runs <- l.runs + n;
    l.runs >= runs_before
  end

let warmed (ctx : ctx) l ver outer =
  if not (free ctx.w) then None else match loaded () with Some j -> j.pick ctx l ver outer | None -> None

let id l = l.expr.id
let place ctx code l n hi = (the ()).place ctx code l n hi
let is_root code l = match l.code with Some c -> c == code | None -> false
let after code from = (the ()).after code from
let enter ctx l code entry = (the ()).enter ctx l code entry
let start code = (the ()).start code
let counter ctx code l = (the ()).counter ctx code l
