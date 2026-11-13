type state = Working | Made of nativeint array | Refused

(* Set by [start], cleared by the domain that made the level 2, at its end. *)
let running = Atomic.make false

let busy () = Atomic.get running

(* The domain touches nothing of the unit: it reads the text, which nothing changes, and sets the state. In OCaml 5 any
   domain may run a signal's handler: one that raises in this domain still ends the job and clears [running], and its
   exception reaches the main domain under [wait], at the join. *)
let start ~wait text entry =
  if not (Atomic.compare_and_set running false true) then None
  else begin
    let job = Atomic.make Working in
    let work () =
      Fun.protect
        ~finally:(fun () ->
          ignore (Atomic.compare_and_set job Working Refused);
          Atomic.set running false)
        (fun () -> Atomic.set job (match Jit.load text [| entry |] 2 with a -> Made a | exception Failure _ -> Refused))
    in
    (match Domain.spawn work with
     | d -> if wait then Domain.join d
     | exception Failure _ ->
       Atomic.set job Refused;
       Atomic.set running false);
    Some job
  end
