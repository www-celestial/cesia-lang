open Cesia

(* Ordered by time, then by number: the order of OCaml's compare, without its generic walk of the pair, which a server
   paid at each of the timers a request sets. *)
module Timers = Map.Make (struct
    type t = float * int

    let compare (a, i) (b, j) = match Float.compare a b with 0 -> Int.compare i j | c -> c
  end)

(* The wakes that other domains ask for: a domain pushes its wake on [asked], then writes a byte in the pipe, which the
   scheduler watches while [awaited] wakes may still come. *)
type remote = {
  pipe : Unix.file_descr * Unix.file_descr;
  asked : (unit -> unit) list Atomic.t;
  mutable awaited : int;
  mutable armed : bool;
}

type t = {
  mutable backend : Backend.state option;  (* created at first use: most programs never need one *)
  mutable remote : remote option;  (* created at first use too *)
  readers : (Unix.file_descr, (unit -> unit) list) Hashtbl.t;
  writers : (Unix.file_descr, (unit -> unit) list) Hashtbl.t;
  mutable timers : (unit -> unit) Timers.t;
  mutable next_timer : int;
  mutable interrupted : bool;
  mutable tick : (float * (unit -> unit)) option;  (* called at least this often while blocked *)
  mutable on_interrupt : unit -> unit;  (* what a stop signal does from the scheduler, not from its handler *)
}

(* The longest single wait: system calls refuse or overflow far beyond it, and a longer sleep just waits again. *)
let max_wait = 86400.

let create () =
  { backend = None; remote = None; readers = Hashtbl.create 64; writers = Hashtbl.create 64; timers = Timers.empty; next_timer = 0;
    interrupted = false; tick = None; on_interrupt = ignore }

let backend p =
  match p.backend with
  | Some b -> b
  | None ->
    let b = Backend.create () in
    p.backend <- Some b;
    b

let watch p fd =
  Unix.set_nonblock fd;
  Backend.add (backend p) fd

let watch_listener p fd =
  Unix.set_nonblock fd;
  Backend.add_listener (backend p) fd

let park table fd resume =
  let waiting = Option.value (Hashtbl.find_opt table fd) ~default:[] in
  Hashtbl.replace table fd (resume :: waiting)

let read_ready p ctx fd = Fiber.suspend ctx (park p.readers fd)
let notify p fd f = park p.readers fd f
let write_ready p ctx fd = Fiber.suspend ctx (park p.writers fd)

let any_ready p ctx ~read ~write =
  Fiber.suspend ctx (fun resume ->
      let woken = ref false in
      let once () =
        if not !woken then begin
          woken := true;
          resume ()
        end
      in
      List.iter (fun fd -> park p.readers fd once) read;
      List.iter (fun fd -> park p.writers fd once) write)

let sleep p ctx seconds =
  if seconds <= 0. then Fiber.suspend ctx (fun resume -> resume ())
  else begin
    let at = Unix.gettimeofday () +. seconds in
    Fiber.suspend ctx (fun resume ->
        p.next_timer <- p.next_timer + 1;
        p.timers <- Timers.add (at, p.next_timer) resume p.timers)
  end

let timer p seconds f =
  p.next_timer <- p.next_timer + 1;
  let key = Unix.gettimeofday () +. seconds, p.next_timer in
  p.timers <- Timers.add key f p.timers;
  fun () -> p.timers <- Timers.remove key p.timers

let wake table fd =
  match Hashtbl.find_opt table fd with
  | None -> ()
  | Some waiting ->
    Hashtbl.remove table fd;
    List.iter (fun resume -> resume ()) (List.rev waiting)

let forget p fd =
  Backend.remove (backend p) fd;
  wake p.readers fd;
  wake p.writers fd

let interrupt p = p.interrupted <- true
let on_interrupt p f = p.on_interrupt <- f
let set_tick p period f = p.tick <- Some (period, f)

let fire_timers p =
  let now = Unix.gettimeofday () in
  let rec go () =
    match Timers.min_binding_opt p.timers with
    | Some (((at, _) as key), resume) when at <= now ->
      p.timers <- Timers.remove key p.timers;
      resume ();
      go ()
    | _ -> ()
  in
  go ()

let waiting p () =
  let keys table = Hashtbl.fold (fun fd _ acc -> fd :: acc) table [] in
  keys p.readers, keys p.writers

let idle p block =
  let fds = Hashtbl.length p.readers + Hashtbl.length p.writers in
  let next = Timers.min_binding_opt p.timers in
  let until_timer =
    match next with
    | _ when not block -> Some 0.
    | Some ((at, _), _) -> Some (Float.min max_wait (Float.max 0. (at -. Unix.gettimeofday ())))
    | None -> None
  in
  let tick_period = match p.tick with Some (period, _) when block -> Some period | _ -> None in
  let timeout =
    match until_timer, tick_period with
    | Some t, Some period -> Some (Float.min t period)
    | Some t, None -> Some t
    | None, period -> period
  in
  if block && fds = 0 && next = None then false
  else begin
    (match timeout with
     | _ when fds > 0 ->
       let ready = Backend.wait (backend p) (Option.value timeout ~default:(-1.)) (waiting p) in
       List.iter
         (fun fd ->
            wake p.readers fd;
            wake p.writers fd)
         ready
     | Some t when t > 0. -> Unix.sleepf t
     | _ -> ());
    if p.interrupted then begin
      p.interrupted <- false;
      p.on_interrupt ();
      List.iter (wake p.readers) (Hashtbl.fold (fun fd _ acc -> fd :: acc) p.readers [])
    end;
    if next <> None then fire_timers p;
    if block then Option.iter (fun (_, f) -> f ()) p.tick;
    true
  end

(* The pipe stays open: a domain may still write in it. A wake asked for before a reset goes on the list of its own record,
   which nothing reads any more, and that record, disarmed, never takes the pipe from the new one. *)
let rec arm p r =
  if r.awaited > 0 && not r.armed then begin
    r.armed <- true;
    notify p (fst r.pipe) (fun () ->
        r.armed <- false;
        let bytes = Bytes.create 64 in
        let rec drain () = match Unix.read (fst r.pipe) bytes 0 64 with 64 -> drain () | _ -> () | exception Unix.Unix_error _ -> () in
        drain ();
        List.iter (fun wake -> r.awaited <- r.awaited - 1; wake ()) (List.rev (Atomic.exchange r.asked []));
        arm p r)
  end

let remote p wake =
  let r =
    match p.remote with
    | Some r -> r
    | None ->
      let (input, output) as pipe = Unix.pipe ~cloexec:true () in
      watch p input;
      Unix.set_nonblock output;
      let r = { pipe; asked = Atomic.make []; awaited = 0; armed = false } in
      p.remote <- Some r;
      r
  in
  r.awaited <- r.awaited + 1;
  arm p r;
  let fired = Atomic.make false in
  fun () ->
    if not (Atomic.exchange fired true) then
      if Domain.is_main_domain () then begin
        r.awaited <- r.awaited - 1;
        if r.awaited = 0 && r.armed then (Hashtbl.remove p.readers (fst r.pipe); r.armed <- false);
        wake ()
      end
      else begin
        let rec push () = let l = Atomic.get r.asked in if not (Atomic.compare_and_set r.asked l (wake :: l)) then push () in
        push ();
        try ignore (Unix.single_write_substring (snd r.pipe) "w" 0 1) with Unix.Unix_error _ -> ()
      end

let reset p =
  Option.iter (fun r -> r.armed <- false; p.remote <- Some { r with asked = Atomic.make []; awaited = 0 }) p.remote;
  Hashtbl.reset p.readers;
  Hashtbl.reset p.writers;
  p.timers <- Timers.empty
