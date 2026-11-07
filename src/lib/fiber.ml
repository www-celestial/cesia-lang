open Types
open Effect
open Effect.Deep

(* A fiber parks through an effect: [register] gets the function that wakes it. *)
type _ Effect.t += Suspend : ((unit -> bool) -> unit) -> unit Effect.t

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
  if ctx.fiber then perform (Suspend register)
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
    if not (Queue.is_empty w.sched.ready) then park ctx (fun wake -> ignore (wake ()))
  end

(* Runs a fiber until it ends or parks. A panic is handled by the body, so what leaves here stops the program. *)
let start w ctx body =
  let s = w.sched in
  s.current <- Some ctx;
  match_with body ()
    { retc = Fun.id;
      exnc = raise;
      effc =
        (fun (type a) (e : a Effect.t) ->
           match e with
           | Suspend register ->
             Some
               (fun (k : (a, unit) continuation) ->
                  let n = parked ctx in
                  register (fun () ->
                      woken ctx n
                      && begin
                        Queue.add
                          (fun () ->
                             s.current <- Some ctx;
                             continue k ())
                          s.ready;
                        true
                      end))
           | _ -> None) }

(* What [Wait] gives for a panic: the same fields as an error shown to the user. *)
let panic_keys = Trie.names [| "Message"; "Kind"; "File"; "Line" |]

let panic_value w text kind at =
  let site = Dynarray.get w.sites at in
  let path, _ = Dynarray.get w.files site.sfile in
  Trie.record panic_keys [| Text text; Text (Value.kind_name kind); Text path; Int (Pos.line site.spos) |]

(* The stacks of a new fiber, in entries. They grow on demand, and a server has thousands of idle fibers. *)
let fiber_stack = 64

(* What a new fiber takes in memory, as measured by tools/fiber-size.sh. *)
let fiber_words = 450

let spawn (ctx : ctx) g =
  let w = ctx.w in
  (match g with
   | Fun _ | Native _ -> ()
   | v -> Runtime.fail ctx Type (Messages.not_function (Value.describe v)));
  Runtime.build ctx fiber_words;
  let s = w.sched in
  let id = s.next_id in
  s.next_id <- id + 1;
  let task = { result = None; waiters = [] } in
  let fiber = Runtime.create_ctx ~stack:fiber_stack ~fiber:true ~id w in
  fiber.site <- ctx.site;
  let finish r =
    Runtime.settle fiber;
    task.result <- Some r;
    List.iter (fun wake -> wake ()) (List.rev task.waiters);
    task.waiters <- []
  in
  let body () =
    match Compile.call_value fiber ~base:2 g [||] with
    | v -> finish (Value.ok w v)
    | exception (Value.Kerr { text; kind; at; _ } as e) ->
      w.on_panic fiber e;
      finish (Value.err w (panic_value w text kind at))
    | exception (Value.Limit { what = "nesting"; _ } as e) ->
      (* A value too deep to show is the problem of this fiber. The steps and the memory belong to the whole program. *)
      w.on_panic fiber e;
      finish (Value.err w (panic_value w (Messages.limit "nesting").text Type fiber.site))
  in
  Queue.add (fun () -> start w fiber body) s.ready;
  Handle { kind = "task"; id; task = Some (Job task) }

let wait (ctx : ctx) t =
  match t with
  | Handle { kind = "task"; task = Some (Job task); _ } ->
    if Option.is_none task.result then suspend ctx (fun resume -> task.waiters <- resume :: task.waiters);
    (match task.result with
     | Some r -> Value.share r
     | None -> Runtime.fail ctx Type (Messages.need_task (Value.describe t)))
  | v -> Runtime.fail ctx Type (Messages.need_task (Value.describe v))

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

(* A timeout in seconds, or None for none. *)
let seconds_arg ctx (v : Types.t) =
  match v with
  | Undef | Missing -> None
  | Int i when i >= 0 -> Some (float_of_int i)
  | Float x when x >= 0. -> Some x
  | v -> Runtime.fail ctx Type (Messages.bad_timeout (Value.describe v))

type taken = Came of Types.t | Closed | Late

(* Parks until a value comes, the channel is closed, or [limit] seconds pass, with one timer for the whole wait. A receiver
   woken may find the value taken by one that never parked: it parks again, at the front, since it came first. *)
let await ctx ch limit =
  let timed_out = ref false and parked = ref None in
  Option.iter
    (fun seconds ->
       ctx.w.timer seconds (fun () ->
           timed_out := true;
           Option.iter
             (fun wake ->
                ch.receivers <- List.filter (fun w -> w != wake) ch.receivers;
                ignore (wake ()))
             !parked))
    limit;
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
  go false

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

(* Nothing more comes: the receivers parked wake to what is left, then to its end; the senders parked find it closed. *)
let close ctx (a : Types.t array) =
  let ch = channel_arg ctx "Close" a.(0) in
  if ch.closed then Runtime.fail ctx User Messages.closed_twice;
  ch.closed <- true;
  let receivers = ch.receivers in
  ch.receivers <- [];
  List.iter (fun wake -> ignore (wake ())) receivers;
  Queue.iter (fun s -> ignore (s.wake ())) ch.senders;
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
    "Wait", Native.nat ~result:true "Wait" 1 1 (fun ctx a -> wait ctx a.(0));
    "Channel", Native.nat ~params:[| "size" |] "Channel" 0 1 channel;
    "Send", Native.nat ~params:[| "value"; "ch" |] "Send" 2 2 send;
    "Receive", Native.nat ~result:true ~params:[| "ch"; "timeout" |] "Receive" 1 2 receive;
    "Close", Native.nat ~params:[| "ch" |] "Close" 1 1 close ]
