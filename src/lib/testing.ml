open Types

type config = {
  path : string;
  cases : int;
  only : string option;
  worker : bool;
  update : bool;
  dir : string;
  timeout : float;
  clock : unit -> float;
  remove : string -> unit;
}

type runner = { run : world -> config -> int; units : string -> string list; tick : unit -> unit; reset : (unit -> unit) ref }

let runner = ref None
let is_test name = String.length name > 2 && name.[0] = 'i' && name.[1] = 's' && name.[2] >= 'A' && name.[2] <= 'Z'
