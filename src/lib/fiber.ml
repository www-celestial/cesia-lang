open Types
open Effect
open Effect.Deep

type _ Effect.t += Suspend : ((unit -> unit) -> unit) -> unit Effect.t

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

(* A spawned fiber suspends through an effect. The main program isn't a fiber, which keeps its stack and its speed:
   it runs the scheduler itself until it is woken, in FIFO order with the others. *)
let suspend (ctx : ctx) register =
  if ctx.fiber then perform (Suspend register)
  else begin
    let w = ctx.w in
    let woken = ref false in
    register (fun () -> Queue.add (fun () -> woken := true) w.sched.ready);
    while not !woken do
      if not (step w) then begin
        w.sched.current <- Some ctx;
        Runtime.fail ctx User Messages.deadlock
      end
    done;
    w.sched.current <- Some ctx
  end

(* A long computation lets the others run at each full checkpoint, except while the debugger holds the program. *)
let yield (ctx : ctx) =
  let w = ctx.w in
  if not w.debug.stopped then begin
    ignore (w.idle false);
    if not (Queue.is_empty w.sched.ready) then suspend ctx (fun resume -> resume ())
  end

(* Runs a fiber until it ends or suspends. A panic is handled by the body, so what leaves here stops the program. *)
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
                  register (fun () ->
                      Queue.add
                        (fun () ->
                           s.current <- Some ctx;
                           continue k ())
                        s.ready))
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
  let task = { result = None; waiters = []; items = Queue.create () } in
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
    | exception (Value.Limit { what = ("nesting" | "memory") as what; _ } as e) ->
      (* A value too deep to show is the problem of this fiber, and so is the memory it was taking when the limit came:
         a server's request that takes too much stops alone, and frees what it took. The steps belong to the whole
         program. *)
      w.on_panic fiber e;
      finish (Value.err w (panic_value w (Messages.limit what).text (if what = "memory" then Math else Type) fiber.site))
  in
  Queue.add (fun () -> start w fiber body) s.ready;
  Handle { kind = "task"; id; task = Some task }

(* A timeout in seconds, or None for none. *)
let seconds_arg ctx (v : Types.t) =
  match v with
  | Undef | Missing -> None
  | Int i when i >= 0 -> Some (float_of_int i)
  | Float x when x >= 0. -> Some x
  | v -> Runtime.fail ctx Type (Messages.bad_timeout (Value.describe v))

let timeout_keys = Trie.names [| "Kind"; "Message" |]
let timeout_err ctx message = Value.err ctx.w (Trie.record timeout_keys [| Text "timeout"; Text message.Messages.text |])

(* Parks until the task ends, or until the timeout: the first of the two wakes the fiber, and cancels the other. *)
let wait ?timeout (ctx : ctx) t =
  match t with
  | Handle { kind = "task"; task = Some task; _ } ->
    (match task.result, timeout with
     | Some _, _ | None, Some 0. -> ()
     | None, None -> suspend ctx (fun resume -> task.waiters <- resume :: task.waiters)
     | None, Some seconds ->
       suspend ctx (fun resume ->
           let parked = ref true and cancel = ref ignore in
           let wake () = if !parked then (parked := false; !cancel (); resume ()) in
           task.waiters <- wake :: task.waiters;
           cancel :=
             ctx.w.timer seconds (fun () ->
                 if !parked then begin
                   parked := false;
                   task.waiters <- List.filter (fun w -> w != wake) task.waiters;
                   resume ()
                 end)));
    (match task.result with
     | Some r -> Value.share r
     | None when timeout <> None -> timeout_err ctx Messages.wait_timeout
     | None -> Runtime.fail ctx Type (Messages.need_task (Value.describe t)))
  | v -> Runtime.fail ctx Type (Messages.need_task (Value.describe v))

(* Channels: a queue between fibers. Send never waits; Receive parks until a value comes, or until its timeout. *)
let channel_arg ctx name (v : Types.t) =
  match v with
  | Handle { kind = "channel"; task = Some ch; _ } -> ch
  | v -> Runtime.fail ctx Type (Messages.need_channel name (Value.describe v))

(* A channel never has a result: Close sets it, to say that nothing more comes. *)
let closed (ch : task) = ch.result <> None

let send ctx (a : Types.t array) =
  let ch = channel_arg ctx "Send" a.(1) in
  if closed ch then Runtime.fail ctx User Messages.send_closed;
  Queue.add (Value.share a.(0)) ch.items;
  (match ch.waiters with
   | wake :: rest -> ch.waiters <- rest; wake ()
   | [] -> ());
  Missing

let receive ctx (a : Types.t array) =
  let ch = channel_arg ctx "Receive" a.(0) in
  let limit = seconds_arg ctx (if Array.length a > 1 then a.(1) else Undef) in
  let timed_out = ref (limit = Some 0.) in
  (* One timer for the whole wait. A receiver woken may find the value taken by one that never parked: it parks again, at
     the front, since it came first. *)
  let parked_wake = ref None and timing = ref false and cancel = ref ignore in
  let rec take again =
    match Queue.take_opt ch.items with
    | Some v -> !cancel (); Value.ok ctx.w v
    | None when closed ch -> !cancel (); Value.failure ctx.w "closed" Messages.channel_closed.text
    | None when !timed_out -> timeout_err ctx Messages.receive_timeout
    | None ->
      suspend ctx (fun resume ->
          let parked = ref true in
          let wake () = if !parked then (parked := false; parked_wake := None; resume ()) in
          parked_wake := Some wake;
          ch.waiters <- (if again then wake :: ch.waiters else ch.waiters @ [ wake ]);
          if not !timing then begin
            timing := true;
            Option.iter
              (fun seconds ->
                 cancel :=
                   ctx.w.timer seconds (fun () ->
                       timed_out := true;
                       Option.iter
                         (fun wake ->
                            ch.waiters <- List.filter (fun w -> w != wake) ch.waiters;
                            wake ())
                         !parked_wake))
              limit
          end);
      take true
  in
  take false

(* Nothing more comes: the receivers parked wake to what is left, then to its end. *)
let close ctx (a : Types.t array) =
  let ch = channel_arg ctx "Close" a.(0) in
  if closed ch then Runtime.fail ctx User Messages.closed_twice;
  ch.result <- Some Missing;
  let waiting = ch.waiters in
  ch.waiters <- [];
  List.iter (fun wake -> wake ()) waiting;
  Missing

let natives =
  [ "Spawn", Native.nat "Spawn" 1 1 (fun ctx a -> spawn ctx a.(0));
    "Wait",
    Native.nat ~result:true ~params:[| "task"; "timeout" |] "Wait" 1 2 (fun ctx a ->
        wait ?timeout:(seconds_arg ctx (if Array.length a > 1 then a.(1) else Undef)) ctx a.(0));
    "Channel",
    Native.nat "Channel" 0 0 (fun ctx _ ->
        let s = ctx.w.sched in
        s.next_id <- s.next_id + 1;
        Handle { kind = "channel"; id = s.next_id - 1; task = Some { result = None; waiters = []; items = Queue.create () } });
    "Send", Native.nat ~params:[| "value"; "ch" |] "Send" 2 2 send;
    "Receive", Native.nat ~result:true ~params:[| "ch"; "timeout" |] "Receive" 1 2 receive;
    "Close", Native.nat ~params:[| "ch" |] "Close" 1 1 close ]
