external ram : unit -> int = "cesia_ram"

open Cesia
open Types

let seconds ctx v =
  let bad () = Runtime.fail ctx Type (Messages.bad_sleep (Value.describe v)) in
  match v with
  | Int i when i >= 0 -> float_of_int i
  | Float x when x >= 0. && x < infinity -> x
  | _ -> bad ()

let register ?(max_sleep = infinity) ?tick ?(watching = false) w =
  let poll = Poll.create () in
  w.idle <- Poll.idle poll;
  Option.iter (fun (period, f) -> Poll.set_tick poll period f) tick;
  let net = Net.create poll in
  let sys =
    Fs.natives @ Proc.natives poll
    @ [ "Now", Native.nat "Now" 0 0 (fun _ _ -> Float (Unix.gettimeofday ()));
        "Sleep",
        Native.nat "Sleep" 1 1 (fun ctx a ->
            Poll.sleep poll ctx (Float.min max_sleep (seconds ctx a.(0)));
            Missing);
        "TakeStops",
        Native.nat "TakeStops" 1 1 (fun ctx a ->
            let taken =
              match a.(0) with
              | True -> true
              | False -> false
              | v -> Runtime.fail ctx Type (Messages.c_need_bool (Value.describe v))
            in
            if watching then Net.take_stops net taken;
            Missing);
        "StopAsked", Native.nat "StopAsked" 0 0 (fun _ _ -> Value.of_bool (Net.stop_asked net)) ]
  in
  Linalg.install ();
  w.native_modules <-
    ("sys", sys) :: ("net", Net.natives net) :: ("c", C.natives (C.create ())) :: ("lapack", Linalg.natives) :: w.native_modules;
  fun () -> Net.stopping net
