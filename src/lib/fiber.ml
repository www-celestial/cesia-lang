open Types
open Effect
open Effect.Deep

(* A fiber parks through an effect: [register] gets the function that wakes it. *)
type _ Effect.t += Suspend : ctx * ((unit -> bool) -> unit) -> unit Effect.t

(* Raised where a fiber that fiber.Cancel stopped was waiting: it unwinds the fiber, as a panic does, but quietly. *)
exception Cancelled

(* How often the scheduler looks at I/O while fibers are ready, in jobs. *)
let poll_period = 256

(* Runs what is ready, or shows what was printed and waits for something to be. False if nothing can ever run again. *)
let step w =
  let s = w.sched in
  s.jobs <- s.jobs + 1;
  if s.jobs mod poll_period = 0 then ignore (w.idle false);
  match Queue.take_opt s.ready with
  | Some job -> job (); true
  | None ->
    Runtime.flush_out w;
    w.idle true

(* A wait takes a number, odd while it lasts: its wake queues the fiber the first time only, and says whether it did. A
   fiber parked in several places, or on a timer too, is woken once, and a channel that finds a fiber gone passes its
   value on to the next one. *)
let parked (ctx : ctx) =
  let n = ctx.parks + 1 in
  ctx.parks <- n;
  n

let[@inline] woken (ctx : ctx) n = ctx.parks = n && (ctx.parks <- n + 1; true)

(* A spawned fiber parks through an effect. The main program isn't a fiber, which keeps its stack and its speed:
   it runs the scheduler itself until it is woken, in FIFO order with the others. *)
let park (ctx : ctx) register =
  if ctx.fiber then perform (Suspend (ctx, register))
  else begin
    let w = ctx.w in
    let woke = ref false in
    let n = parked ctx in
    register (fun () -> woken ctx n && (Queue.add (fun () -> woke := true) w.sched.ready; true));
    while not !woke do
      if not (step w) then begin
        w.sched.current <- Some ctx;
        Runtime.fail ctx User Messages.deadlock
      end
    done;
    w.sched.current <- Some ctx
  end

let suspend ctx register = park ctx (fun wake -> register (fun () -> ignore (wake ())))

(* A long computation lets the others run at each full checkpoint, except while the debugger holds the program. *)
let yield (ctx : ctx) =
  let w = ctx.w in
  if not w.debug.stopped then begin
    ignore (w.idle false);
    if ctx.cancelled || not (Queue.is_empty w.sched.ready) then park ctx (fun wake -> ignore (wake ()))
  end

(* The handler of every fiber, made once: a fiber that parks gets the wake that queues it again, kept in its context so
   that Cancel can wake it; it resumes with Cancelled if it was asked to stop. A panic is handled by the body, so what
   leaves here stops the program. *)
let handler =
  { retc = Fun.id;
    exnc = raise;
    effc =
      (fun (type a) (e : a Effect.t) ->
         match e with
         | Suspend (ctx, register) ->
           Some
             (fun (k : (a, unit) continuation) ->
                let s = ctx.w.sched and n = parked ctx in
                let wake () =
                  woken ctx n
                  && begin
                    Queue.add (fun () -> s.current <- Some ctx; if ctx.cancelled then discontinue k Cancelled else continue k ()) s.ready;
                    true
                  end
                in
                ctx.wake <- wake;
                register wake)
         | _ -> None) }

(* Runs a fiber until it ends or parks. *)
let start ctx body =
  ctx.w.sched.current <- Some ctx;
  match_with body () handler

(* What [Wait] gives for a panic: the same fields as an error shown to the user. *)
let panic_keys = Trie.names [| "Message"; "Kind"; "File"; "Line" |]

let ended_value w text kind at =
  let site = Vec.get w.sites at in
  let path, _ = Vec.get w.files site.sfile in
  Trie.record panic_keys [| Text text; Text kind; Text path; Int (Pos.line site.spos) |]

let panic_value w text kind at = ended_value w text (Value.kind_name kind) at

let not_parked () = false

(* The stacks of a new fiber, in entries. They grow on demand, and a server has thousands of idle fibers. *)
let fiber_stack = 8

(* What a new fiber takes in memory, as measured by tools/fiber-size.sh. *)
let fiber_words = 270

(* The end of a fiber: its result kept in its task, which lets go of the fiber, and the fibers waiting for it woken. *)
let finish fiber task r =
  Runtime.settle fiber;
  task.result <- Some r;
  task.cx <- None;
  List.iter (fun wake -> ignore (wake ())) (List.rev task.waiters);
  task.waiters <- []

(* What a fiber runs: its function, then its result or the error that stopped it. *)
let body task fiber g () =
  let w = fiber.w in
  match if fiber.cancelled then raise Cancelled else Compile.call_value fiber ~base:2 g [||] with
  | v -> finish fiber task (Value.ok w v)
  | exception Cancelled -> finish fiber task (Value.err w (ended_value w Messages.cancelled.text "cancelled" fiber.site))
  | exception (Value.Kerr { text; kind; at; _ } as e) ->
    w.on_panic fiber e;
    finish fiber task (Value.err w (panic_value w text kind at))
  | exception (Value.Limit { what = ("nesting" | "memory") as what; _ } as e) ->
    (* A value too deep to show is the problem of this fiber, and so is the memory it was taking when the limit came:
       a server's request that takes too much stops alone, and frees what it took. The steps belong to the whole
       program. *)
    w.on_panic fiber e;
    finish fiber task (Value.err w (panic_value w (Messages.limit what).text (if what = "memory" then Math else Type) fiber.site))

let spawn (ctx : ctx) g =
  let w = ctx.w in
  (match g with
   | Fun _ | Native _ -> ()
   | v -> Runtime.fail ctx Type (Messages.not_function (Value.describe v)));
  Runtime.build ctx fiber_words;
  let s = w.sched in
  let id = s.next_id in
  s.next_id <- id + 1;
  let fiber = Runtime.create_ctx ~stack:fiber_stack ~fiber:true ~id w in
  fiber.site <- ctx.site;
  let task = { result = None; waiters = []; cx = Some fiber } in
  Queue.add (fun () -> start fiber (body task fiber g)) s.ready;
  Handle { kind = "task"; id; task = Some (Job task) }

(* A timeout in seconds, or None for none. *)
let seconds_arg ctx (v : Types.t) =
  match v with
  | Undef | Missing -> None
  | Int i when i >= 0 -> Some (float_of_int i)
  | Float x when x >= 0. -> Some x
  | v -> Runtime.fail ctx Type (Messages.bad_timeout (Value.describe v))

let job_arg ctx name (v : Types.t) =
  match v with
  | Handle { kind = "task"; task = Some (Job job); _ } -> job
  | v -> Runtime.fail ctx Type (Messages.need_task name (Value.describe v))

(* Parks until the task ends, or until the timeout: the first of the two wakes the fiber, and takes the other away. *)
let wait ?timeout (ctx : ctx) t =
  let job = job_arg ctx "Wait" t in
  (match job.result, timeout with
   | Some _, _ | None, Some 0. -> ()
   | None, None -> park ctx (fun wake -> job.waiters <- wake :: job.waiters)
   | None, Some seconds ->
     let stop_timer = ref ignore and mine = ref not_parked in
     let leave () =
       !stop_timer ();
       job.waiters <- List.filter (fun w -> w != !mine) job.waiters
     in
     match
       park ctx (fun wake ->
           (mine := fun () -> !stop_timer (); wake ());
           job.waiters <- !mine :: job.waiters;
           stop_timer := ctx.w.timer seconds (fun () -> leave (); ignore (wake ())))
     with
     | () -> ()
     | exception e -> leave (); raise e);
  match job.result with
  | Some r -> Value.share r
  | None -> Value.failure ctx.w "timeout" Messages.wait_timeout.text

(* A fiber that asks itself to stop does at once; another one, at its wait, or at its start if it hasn't begun. *)
let cancel ctx (a : Types.t array) =
  (match (job_arg ctx "Cancel" a.(0)) with
   | { cx = Some cx; _ } when not cx.cancelled ->
     cx.cancelled <- true;
     if cx == ctx then raise Cancelled else ignore (cx.wake ())
   | _ -> ());
  Missing

(* Channels: a queue between fibers. Send waits only while a bounded channel is full; Receive parks until a value comes,
   or until its timeout. *)
let channel_arg ctx name (v : Types.t) =
  match v with
  | Handle { kind = "channel"; task = Some (Chan ch); _ } -> ch
  | v -> Runtime.fail ctx Type (Messages.need_channel name (Value.describe v))

(* Wakes the oldest receiver still parked. *)
let rec wake_receiver ch =
  match ch.receivers with
  | [] -> ()
  | wake :: rest ->
    ch.receivers <- rest;
    if not (wake ()) then wake_receiver ch

(* The value of the oldest sender still parked, which goes on its way. *)
let rec from_sender ch =
  match Queue.take_opt ch.senders with
  | None -> None
  | Some s ->
    if s.wake () then begin
      s.taken <- true;
      Some s.sent
    end
    else from_sender ch

(* The oldest value of a channel, if it has one. A full channel takes in the value of its oldest parked sender. *)
let next ch =
  match Queue.take_opt ch.items with
  | Some v ->
    if not (Queue.is_empty ch.senders) then Option.iter (fun s -> Queue.add s ch.items) (from_sender ch);
    Some v
  | None -> from_sender ch

(* Does a channel have a value for a receiver? *)
let has_value ch = not (Queue.is_empty ch.items && Queue.is_empty ch.senders)

(* A receiver that leaves by a cancel, perhaps woken for a value it never took, passes the wake on to the next one. *)
let leave chs wake =
  List.iter
    (fun ch ->
       ch.receivers <- List.filter (fun w -> w != wake) ch.receivers;
       if has_value ch then wake_receiver ch)
    chs

let send ctx (a : Types.t array) =
  let ch = channel_arg ctx "Send" a.(1) in
  if ch.closed then Runtime.fail ctx User Messages.send_closed;
  let v = Value.share a.(0) in
  if Queue.length ch.items < ch.size then begin
    Queue.add v ch.items;
    wake_receiver ch
  end
  else begin
    (* Full: the value waits with its fiber, which a receiver wakes as it takes it. Of size 0, it waits for one. *)
    let me = ref None in
    park ctx (fun wake ->
        let s = { sent = v; taken = false; wake } in
        me := Some s;
        Queue.add s ch.senders;
        wake_receiver ch);
    match !me with
    | Some { taken = true; _ } -> ()
    | _ -> Runtime.fail ctx User Messages.send_closed
  end;
  Missing

type taken = Came of Types.t | Closed | Late

(* Parks until a value comes, the channel is closed, or [limit] seconds pass, with one timer for the whole wait. A receiver
   woken may find the value taken by one that never parked: it parks again, at the front, since it came first. *)
let await ctx ch limit =
  let timed_out = ref false and parked = ref None in
  let stop_timer =
    match limit with
    | None -> ignore
    | Some seconds ->
      ctx.w.timer seconds (fun () ->
          timed_out := true;
          Option.iter
            (fun wake ->
               ch.receivers <- List.filter (fun w -> w != wake) ch.receivers;
               ignore (wake ()))
            !parked)
  in
  let rec go again =
    park ctx (fun wake ->
        parked := Some wake;
        ch.receivers <- (if again then wake :: ch.receivers else ch.receivers @ [ wake ]));
    match next ch with
    | Some v -> Came v
    | None when ch.closed -> Closed
    | None when !timed_out -> Late
    | None -> go true
  in
  match go false with
  | got -> stop_timer (); got
  | exception e ->
    stop_timer ();
    Option.iter (leave [ ch ]) !parked;
    raise e

(* The oldest value of a channel, waiting at most [limit] seconds for one. *)
let take ctx ch limit =
  match next ch with
  | Some v -> Came v
  | None when ch.closed -> Closed
  | None when limit = Some 0. -> Late
  | None -> await ctx ch limit

let receive ctx (a : Types.t array) =
  let ch = channel_arg ctx "Receive" a.(0) in
  match take ctx ch (seconds_arg ctx (if Array.length a > 1 then a.(1) else Undef)) with
  | Came v -> Value.ok ctx.w v
  | Closed -> Value.failure ctx.w "closed" Messages.channel_closed.text
  | Late -> Value.failure ctx.w "timeout" Messages.receive_timeout.text

let next_in ctx v = match take ctx (channel_arg ctx "for" v) None with Came v -> Some v | Closed | Late -> None

let select_keys = Trie.names [| "Channel"; "Value" |]
let closed_keys = Trie.names [| "Kind"; "Message"; "Channel" |]

(* The first channel of the list with a value, or closed and empty, in the order of the list; else it parks on all of
   them, with one timer for the whole wait, and looks again when woken. A fiber woken by one channel may take from an
   earlier one: the others with a value then wake their next receiver, so that none is left waiting for nothing. *)
let select ctx (a : Types.t array) =
  let chs =
    match a.(0) with
    | Array l ->
      let l = Value.trim l in
      List.init (l.rows * l.cols) (fun k ->
          let h = Value.elt l k in
          h, channel_arg ctx "Select" h)
    | v -> Runtime.fail ctx Type (Messages.need_channels (Value.describe v))
  in
  let limit = seconds_arg ctx (if Array.length a > 1 then a.(1) else Undef) in
  let rec first = function
    | [] -> None
    | (h, ch) :: rest ->
      (match next ch with
       | Some v -> Some (h, ch, Came v)
       | None when ch.closed -> Some (h, ch, Closed)
       | None -> first rest)
  in
  let timed_out = ref (limit = Some 0.) and parked = ref None and stop_timer = ref None in
  let rec go again =
    match first chs with
    | Some (h, taken, got) ->
      List.iter (fun (_, ch) -> if ch != taken && has_value ch then wake_receiver ch) chs;
      (match got with
       | Came v -> Value.ok ctx.w (Trie.record select_keys [| h; v |])
       | Closed | Late -> Value.err ctx.w (Trie.record closed_keys [| Text "closed"; Text Messages.channel_closed.text; h |]))
    | None when !timed_out -> Value.failure ctx.w "timeout" Messages.select_timeout.text
    | None ->
      if Option.is_none !stop_timer then
        stop_timer :=
          Some
            (match limit with
             | None -> ignore
             | Some seconds ->
               ctx.w.timer seconds (fun () ->
                   timed_out := true;
                   Option.iter (fun wake -> ignore (wake ())) !parked));
      park ctx (fun wake ->
          parked := Some wake;
          List.iter
            (fun (_, ch) -> ch.receivers <- (if again then wake :: ch.receivers else ch.receivers @ [ wake ]))
            chs);
      Option.iter
        (fun wake -> List.iter (fun (_, ch) -> ch.receivers <- List.filter (fun w -> w != wake) ch.receivers) chs)
        !parked;
      go true
  in
  let stop () = Option.iter (fun f -> f ()) !stop_timer in
  match go false with
  | got -> stop (); got
  | exception e ->
    stop ();
    Option.iter (leave (List.map snd chs)) !parked;
    raise e

(* Nothing more comes: the receivers parked wake to what is left, then to its end; the senders parked find it closed. *)
let close ctx (a : Types.t array) =
  let ch = channel_arg ctx "Close" a.(0) in
  if ch.closed then Runtime.fail ctx User Messages.closed_twice;
  ch.closed <- true;
  let receivers = ch.receivers in
  ch.receivers <- [];
  List.iter (fun wake -> ignore (wake ())) receivers;
  Queue.iter (fun (s : sender) -> ignore (s.wake ())) ch.senders;
  Queue.clear ch.senders;
  Missing

let channel ctx (a : Types.t array) =
  let size =
    match if Array.length a > 0 then a.(0) else Undef with
    | Undef | Missing -> max_int
    | Int n when n >= 0 -> n
    | v -> Runtime.fail ctx Type (Messages.channel_size (Value.describe v))
  in
  let s = ctx.w.sched in
  s.next_id <- s.next_id + 1;
  Handle
    { kind = "channel"; id = s.next_id - 1;
      task = Some (Chan { items = Queue.create (); size; receivers = []; senders = Queue.create (); closed = false }) }

let natives =
  [ "Spawn", Native.nat "Spawn" 1 1 (fun ctx a -> spawn ctx a.(0));
    "Wait",
    Native.nat ~result:true ~params:[| "task"; "timeout" |] "Wait" 1 2 (fun ctx a ->
        wait ?timeout:(seconds_arg ctx (if Array.length a > 1 then a.(1) else Undef)) ctx a.(0));
    "Cancel", Native.nat ~params:[| "task" |] "Cancel" 1 1 cancel;
    "Channel", Native.nat ~params:[| "size" |] "Channel" 0 1 channel;
    "Send", Native.nat ~params:[| "value"; "ch" |] "Send" 2 2 send;
    "Receive", Native.nat ~result:true ~params:[| "ch"; "timeout" |] "Receive" 1 2 receive;
    "Close", Native.nat ~params:[| "ch" |] "Close" 1 1 close;
    "Select", Native.nat ~result:true ~params:[| "chs"; "timeout" |] "Select" 1 2 select ]
