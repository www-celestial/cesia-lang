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

(* The names of the natives of std/test and std/gen, so that their Cesia parts load anywhere, as the site checks its blocks;
   outside cesia test they only say where they work. The plugin's own come first under cesia test. *)
let stub (name, least, most) = name, Native.nat name least most (fun ctx _ -> Runtime.fail ctx User Messages.test_only)

let natives =
  [ "test",
    List.map stub
      [ "start", 0, 0; "oneCase", 4, 4; "save", 2, 2; "drop", 0, 0; "failed", 1, 1; "temp", 0, 0; "snapshot", 1, 1;
        "defaultCases", 0, 0 ];
    "gen", List.map stub [ "draw", 1, 1; "size", 0, 0; "fields", 1, 1; "make", 2, 2 ] ]
