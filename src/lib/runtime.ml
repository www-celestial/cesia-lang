open Types

let default_period = 1_000_000
let initial_stack = 4096

let default_limits = { steps = max_int; memory_words = max_int; max_depth = 10_000; nesting = 600 }

(* 80% of the RAM, in words, from its size in bytes. Unknown RAM, given as 0, means no limit. *)
let default_memory bytes = if bytes > 0 then bytes / 10 else max_int

type options = {
  o_limits : limits;
  o_grants : grants;
  o_no_spec : bool;
  o_debugger : string option;
  o_repl : bool;
  o_period : int;
  o_sink : string -> unit;
  o_err : string -> unit;
}

let default_options =
  { o_limits = default_limits; o_grants = { all = false; perms = [] }; o_no_spec = false; o_debugger = None; o_repl = false;
    o_period = default_period;
    o_sink = (fun s -> print_string s; flush stdout);
    o_err = (fun s -> prerr_string s; flush stderr) }

let flush_out w =
  if Buffer.length w.out > 0 then begin
    w.sink (Buffer.contents w.out);
    Buffer.clear w.out
  end

let[@inline never] fail ctx kind (m : Messages.t) =
  ctx.w.on_error ctx m.text;
  raise (Value.Kerr { kind; text = m.text; hint = m.hint; at = ctx.site })

(* The link to the caller holds its base and, above it, the depth of the frame once counted. A new frame writes a link
   without a depth: the one read is therefore always true, and each frame is counted only once. *)
let depth_shift = 32
let base_mask = (1 lsl depth_shift) - 1
let link_base link = link land base_mask

let frames ctx =
  let i = ctx.i in
  let walked = ref 0 and known = ref 0 and b = ref ctx.b in
  while !b > 0 && !known = 0 do
    let link = i.(!b) in
    known := link lsr depth_shift;
    if !known = 0 then begin
      incr walked;
      b := link
    end
  done;
  let d = !known + !walked in
  let depth = ref d and b = ref ctx.b in
  for _ = 1 to !walked do
    let link = i.(!b) in
    i.(!b) <- link lor (!depth lsl depth_shift);
    decr depth;
    b := link
  done;
  d

let limit what at = raise (Value.Limit { what; at })

let heap_words () = (Gc.quick_stat ()).Gc.heap_words

(* An entry of v beyond [top] belongs to a finished frame: it must not keep an array alive. *)
let clear_above ctx top = if top < ctx.cap then Array.fill ctx.v top (ctx.cap - top) Undef

(* heap_words only sees a big allocation at the next cycle: also count what was just allocated. The limit is reached
   only if the memory stays occupied after a full cycle. *)
let check_memory ctx n top =
  let w = ctx.w in
  let most = w.limits.memory_words in
  if heap_words () + w.big_words > most then begin
    clear_above ctx top;
    Gc.full_major ();
    w.big_words <- 0;
    if (Gc.stat ()).Gc.live_words + n > most then limit "memory" ctx.site
  end

(* The background work, every [period] steps. *)
let full_checkpoint ctx top =
  let w = ctx.w in
  flush_out w;
  if w.limits.memory_words <> max_int then begin
    check_memory ctx 0 top;
    w.big_words <- 0
  end;
  w.on_checkpoint ctx;
  w.yield ctx

(* The checkpoint, with the top of the v stack still in use. A call adds a single frame and counts one step: at depth
   d, the limit can't fall before max_depth - d steps. Bounding fuel this way makes the limit exact without adding
   anything to a call; the price, counting d frames, only matters very close to the limit. *)
let[@inline never] checkpoint ctx top =
  let w = ctx.w in
  let spent = ctx.refill - ctx.fuel in
  if w.steps_left <> max_int then w.steps_left <- w.steps_left - spent;
  if w.steps_left <= 0 then limit "steps" ctx.site;
  let d = frames ctx in
  if d > ctx.max_depth then limit "depth" ctx.i.(ctx.b + 1);
  ctx.until <- ctx.until - spent;
  if ctx.until <= 0 then begin
    ctx.until <- w.period;
    full_checkpoint ctx top
  end;
  ctx.refill <- min (min ctx.until w.steps_left) (ctx.max_depth - d);
  ctx.fuel <- ctx.refill

(* The top of the v stack at the current site, written just before every native and slow path. *)
let site_top ctx =
  let w = ctx.w in
  if ctx.site < Dynarray.length w.sites then ctx.b + (Dynarray.get w.sites ctx.site).soff else ctx.cap

let charge ctx n =
  ctx.fuel <- ctx.fuel - n;
  if ctx.fuel < 0 then checkpoint ctx (site_top ctx)

(* What a fiber spent since its last checkpoint, when it ends. Short fibers would otherwise run for free. *)
let settle ctx =
  let w = ctx.w in
  if w.steps_left <> max_int then begin
    w.steps_left <- w.steps_left - (ctx.refill - ctx.fuel);
    if w.steps_left <= 0 then limit "steps" ctx.site
  end

let create_world o =
  { modules = [||];
    files = Dynarray.create ();
    sites = Dynarray.create ();
    shapes = Hashtbl.create 16;
    limits = o.o_limits;
    grants = o.o_grants;
    no_spec = o.o_no_spec;
    hooks = o.o_debugger <> None;
    debugger = o.o_debugger;
    repl = o.o_repl;
    debug =
      { mode = Starting; stopped = false; breaks = []; on_stop = Missing; last_file = -1; last_line = 0; last_site = -1;
        watches = []; test = (fun _ _ _ -> true); scope = []; typed_uses = []; main = "";
        made = Hashtbl.create 8 };
    on_hook = (fun _ _ -> ());
    hook_count = 0;
    sched = { ready = Queue.create (); next_id = 1; jobs = 0; current = None };
    idle = (fun block -> not block);
    timer = (fun _ _ -> ());
    native_modules = [];
    yield = (fun _ -> ());
    on_panic = (fun _ _ -> ());
    on_error = (fun _ _ -> ());
    out = Buffer.create 4096;
    sink = o.o_sink;
    err = o.o_err;
    period = o.o_period;
    steps_left = o.o_limits.steps;
    big_words = 0;
    on_checkpoint = (fun _ -> ());
    compile_ver = (fun _ _ -> ());
    charge;
    loaded = Hashtbl.create 8;
    methods = Hashtbl.create 16;
    interfaces = Hashtbl.create 8;
    reloads = 0;
    root = "." }

let first_refill w = min (min w.period w.limits.steps) w.limits.max_depth

let create_ctx ?(stack = initial_stack) ?(fiber = false) ?(id = 0) w =
  { v = Array.make stack Undef;
    f = Float.Array.make stack 0.;
    i = Array.make stack 0;
    b = 0;
    cap = stack;
    fuel = first_refill w;
    refill = first_refill w;
    until = w.period;
    site = 0;
    again = false;
    max_depth = w.limits.max_depth;
    fiber;
    id;
    w }

(* Three stacks of [cap] entries. *)
let[@inline never] grow ctx need =
  let cap = max need (2 * ctx.cap) in
  if cap > base_mask then limit "memory" ctx.site;
  if ctx.w.limits.memory_words <> max_int then check_memory ctx (3 * cap) ctx.cap;
  let v = Array.make cap Undef and f = Float.Array.make cap 0. and i = Array.make cap 0 in
  Array.blit ctx.v 0 v 0 ctx.cap;
  Float.Array.blit ctx.f 0 f 0 ctx.cap;
  Array.blit ctx.i 0 i 0 ctx.cap;
  ctx.v <- v;
  ctx.f <- f;
  ctx.i <- i;
  ctx.cap <- cap

let backtrace ctx at =
  let w = ctx.w in
  let place s =
    let path, _ = Dynarray.get w.files s.sfile in
    Printf.sprintf "%s (%s:%d)" s.sfn path (Pos.line s.spos)
  in
  let lines = ref [] in
  if at >= 0 then begin
    let first = Dynarray.get w.sites at in
    if first.sfn <> "" then lines := [ "in " ^ place first ]
  end;
  let b = ref ctx.b in
  while !b > 0 do
    let s = Dynarray.get w.sites ctx.i.(!b + 1) in
    if s.sfn <> "" then lines := ("called from " ^ place s) :: !lines;
    b := link_base ctx.i.(!b)
  done;
  let lines = List.rev !lines in
  let n = List.length lines in
  if n <= 20 then lines
  else List.filteri (fun i _ -> i < 10) lines @ [ Printf.sprintf "... and %d more" (n - 10) ]

(* The site an error shows first: where it was raised, or, when that is in a library of std/ or deps/, the line of the
   program that called into the library, since that is the line to change. The trace still names the library's line. *)
let user_site ctx at =
  let w = ctx.w in
  let library k =
    let path, _ = Dynarray.get w.files (Dynarray.get w.sites k).sfile in
    String.starts_with ~prefix:"std/" path || String.starts_with ~prefix:"deps/" path
  in
  if at < 0 || not (library at) then at
  else begin
    let found = ref at and b = ref ctx.b in
    while !b > 0 && !found = at do
      let k = ctx.i.(!b + 1) in
      if not (library k) then found := k;
      b := link_base ctx.i.(!b)
    done;
    !found
  end

(* A larger dimension can't exist in memory, even if the other is 0. *)
let max_dimension = 1 lsl 40

let cells ctx rows cols =
  if rows > max_dimension || cols > max_dimension
     || (rows <> 0 && cols > Sys.max_floatarray_length / rows)
  then limit "memory" ctx.site;
  rows * cols

(* To call before allocating n words. The heap is only looked at every quarter of the limit. *)
let reserve ctx n =
  let w = ctx.w in
  if w.limits.memory_words <> max_int then begin
    w.big_words <- w.big_words + n;
    if w.big_words >= w.limits.memory_words / 4 then check_memory ctx n (site_top ctx)
  end

let pay ctx n = charge ctx ((n / 16) + 1)
let pay_bytes ctx n = charge ctx ((n / 128) + 1)

let build ctx n =
  pay ctx n;
  reserve ctx n

let alloc_float ctx n x =
  reserve ctx n;
  match Float.Array.make n x with
  | d -> d
  | exception (Out_of_memory | Invalid_argument _) -> limit "memory" ctx.site

let alloc_vals ctx n x =
  reserve ctx n;
  match Array.make n x with
  | d -> d
  | exception (Out_of_memory | Invalid_argument _) -> limit "memory" ctx.site

let alloc_ints ctx n x =
  reserve ctx n;
  match Array.make n x with
  | d -> d
  | exception (Out_of_memory | Invalid_argument _) -> limit "memory" ctx.site

let perm_name = function
  | Read -> "read"
  | Write -> "write"
  | Net -> "net"
  | Exec -> "exec"
  | Env -> "env"
  | Ffi -> "ffi"
  | Debug -> "debug"

(* a/./b/../c becomes a/c. *)
let normalize path =
  let parts = String.split_on_char '/' path in
  let absolute = String.length path > 0 && path.[0] = '/' in
  let rec go acc = function
    | [] -> List.rev acc
    | ("" | ".") :: rest -> go acc rest
    | ".." :: rest ->
      (match acc with
       | p :: tail when p <> ".." -> go tail rest
       | _ -> go (".." :: acc) rest)
    | p :: rest -> go (p :: acc) rest
  in
  let body = String.concat "/" (go [] parts) in
  if absolute then "/" ^ body else if body = "" then "." else body

let inside dir path =
  let dir = normalize dir and path = normalize path in
  let is_absolute = path.[0] = '/' in
  let is_parent = path = ".." || String.starts_with ~prefix:"../" path in
  if dir = "." then not (is_absolute || is_parent)
  else if dir = "/" then is_absolute
  else path = dir || String.starts_with ~prefix:(dir ^ "/") path

(* Does a scope of --allow cover this target? Paths nest, a network scope may name a host alone, the rest is exact. *)
let scope_matches perm scope target =
  match perm with
  | Read | Write -> inside scope target
  | Net ->
    String.equal scope target
    || ((not (String.contains scope ':')) && String.starts_with ~prefix:(scope ^ ":") target)
  | Exec | Env | Ffi | Debug -> String.equal scope target

let granted w perm path =
  w.grants.all
  || List.exists
       (fun (p, scope) ->
          p = perm
          && (match scope, path with
              | None, _ | _, None -> true
              | Some scope, Some target -> scope_matches perm scope target))
       w.grants.perms

let check_perm ctx perm path =
  if not (granted ctx.w perm path) then fail ctx Permission (Messages.denied (perm_name perm) path)

let copy ctx v =
  match v with
  | Array a ->
    build ctx (a.rows * a.cols);
    let store =
      match a.store with
      | F d -> F (Float.Array.sub d 0 (a.rows * a.cols))
      | I d -> I (Array.sub d 0 (a.rows * a.cols))
      | V d ->
        let cells = Array.sub d 0 (a.rows * a.cols) in
        Array.iter (fun x -> ignore (Value.share x)) cells;
        V cells
    in
    Array { rows = a.rows; cols = a.cols; store; a_owned = true; a_tip = true }
  | Struct r ->
    pay ctx (Array.length r.fields);
    Array.iter (fun x -> ignore (Value.share x)) r.fields;
    Struct { shape = r.shape; fields = Array.copy r.fields; r_owned = true }
  | Dict { vals; _ } ->
    pay ctx (Array.length vals);
    Trie.own_copy v
  | _ -> v

let own ctx v =
  match v with
  | Array { a_owned = true; _ } | Struct { r_owned = true; _ } | Dict { d_owned = true; _ } -> v
  | _ -> copy ctx v
