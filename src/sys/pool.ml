open Cesia

(* A domain starts in about 200 µs, and its end empties the young heap of every domain in a stop of the world: what lives
   there is promoted, 2 ms for a server's 1.4 MB. So when calls come in a burst, one starting less than [linger] seconds
   after the end of the last, the domain that is done waits that long for the next. But one that waits still takes part
   in every stop of the world, and the major GC goes about half as fast while one waits (OCaml 5: the manual's chapter on
   parallelism; Sivaramakrishnan et al., Retrofitting Parallelism onto OCaml, ICFP 2020): a call alone starts a domain
   that leaves once done, at most Par.cores () wait, below the cores, and a program that never calls slowly has none. A
   domain waits in a read of a socket of its own, which a job or the end of its time wakes, its signals blocked so that
   they reach the scheduler. The list, the jobs and [ended] change under [lock] alone, where the byte that wakes is
   written too: no socket is closed under a writer. Where a socket can't wait so, a domain leaves once done. *)
type worker = { mutable job : ((unit -> unit) * (unit -> unit)) option; inlet : Unix.file_descr; outlet : Unix.file_descr; mutable domain : unit Domain.t option }

let lock = Mutex.create ()
let idle = ref []
let ended = ref neg_infinity
let linger = 0.002
let most = ref 0
let close w = Unix.close w.inlet; Unix.close w.outlet

(* A domain that waits is on the list again before the end of its job is told: the next call finds it there. *)
let rec serve w (work, finish) =
  (try work () with _ -> ());
  Mutex.lock lock;
  ended := Unix.gettimeofday ();
  match w with
  | Some w when List.length !idle < !most -> idle := w :: !idle; Mutex.unlock lock; finish (); wait w
  | _ -> Mutex.unlock lock; Option.iter close w; finish ()

and wait w =
  let woken = match Unix.read w.inlet (Bytes.create 8) 0 8 with _ -> true | exception Unix.Unix_error (EINTR, _, _) -> true | exception Unix.Unix_error _ -> false in
  Mutex.lock lock;
  match w.job with
  | Some job -> w.job <- None; Mutex.unlock lock; serve (Some w) job
  | None when woken && List.memq w !idle -> Mutex.unlock lock; wait w
  | None -> idle := List.filter (fun x -> x != w) !idle; Mutex.unlock lock; close w

let quiet () = try ignore (Unix.sigprocmask SIG_BLOCK Sys.[ sigint; sigterm; sighup; sigquit; sigusr1; sigusr2; sigalrm; sigchld ]) with _ -> ()

let socket () =
  match Unix.socketpair ~cloexec:true PF_UNIX SOCK_STREAM 0 with
  | inlet, outlet ->
    (try Unix.setsockopt_float inlet SO_RCVTIMEO linger; Unix.set_nonblock outlet; Some (inlet, outlet)
     with Unix.Unix_error _ | Invalid_argument _ -> Unix.close inlet; Unix.close outlet; None)
  | exception (Unix.Unix_error _ | Invalid_argument _) -> None

let run work finish =
  if !most = 0 then most := max 1 (min (Par.cores ()) (Domain.recommended_domain_count () - 1));
  Mutex.lock lock;
  match !idle with
  | w :: rest ->
    idle := rest;
    w.job <- Some (work, finish);
    (try ignore (Unix.single_write_substring w.outlet "w" 0 1) with Unix.Unix_error _ -> ());
    Mutex.unlock lock;
    true
  | [] ->
    let burst = Unix.gettimeofday () -. !ended < linger in
    Mutex.unlock lock;
    let w = if burst then Option.map (fun (inlet, outlet) -> { job = None; inlet; outlet; domain = None }) (socket ()) else None in
    match Domain.spawn (fun () -> quiet (); serve w (work, finish)) with
    | d -> Option.iter (fun w -> w.domain <- Some d) w; true
    | exception Failure _ -> Option.iter close w; false

let stop () =
  Mutex.lock lock;
  let gone = !idle in
  idle := [];
  List.iter (fun w -> try ignore (Unix.single_write_substring w.outlet "s" 0 1) with Unix.Unix_error _ -> ()) gone;
  Mutex.unlock lock;
  List.iter (fun w -> Option.iter Domain.join w.domain) gone
