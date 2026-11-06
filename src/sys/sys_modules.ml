external ram : unit -> int = "cesia_ram"

open Cesia
open Types

(* sqlite3: the names and arities here, the code in the plugin cesia_sqlite.cmxs, loaded at the first call of one of them so
   that start-up never pays for it. Each native finds its code once. *)
let sqlite3 = ref []
let sqlite_loader = ref (fun () -> Error "no plugin in this program")
let sqlite_keys = Trie.names [| "Kind"; "Code"; "Message" |]

let sqlite_native (name, params, min_args, max_args) =
  let code = ref None in
  let run ctx a =
    match !code with
    | Some f -> f ctx a
    | None ->
      let loaded = match !sqlite3 with [] -> !sqlite_loader () | _ -> Ok () in
      (match loaded, List.assoc_opt name !sqlite3 with
       | Ok (), Some f ->
         code := Some f;
         f ctx a
       | Ok (), None -> Runtime.fail ctx Type (Messages.sql_plugin ("no " ^ name))
       | Error reason, _ ->
         Value.err ctx.w (Trie.record sqlite_keys [| Text "sql"; Text "library"; Text (Messages.sql_plugin reason).text |]))
  in
  name, Native.nat ~params name min_args max_args run

let sqlite_natives =
  List.map sqlite_native
    [ "Pool", [| "path"; "size"; "wait" |], 3, 3; "Take", [| "pool" |], 1, 1; "Give", [| "conn"; "pool" |], 2, 2;
      "Query", [| "text"; "params"; "db"; "limit" |], 3, 4; "One", [| "text"; "params"; "db" |], 3, 3;
      "Exec", [| "text"; "params"; "db" |], 3, 3; "Run", [| "text"; "params"; "conn" |], 3, 3;
      "Next", [| "n"; "cursor" |], 2, 2; "Script", [| "text"; "conn" |], 2, 2; "Close", [| "x" |], 1, 1;
      "Version", [||], 0, 0 ]

(* The clock of this machine's time zone at an instant, for std/date: year, month, day, hour, minute, second. A time the
   system can't place gives the clock of UTC. *)
let local_clock ctx (a : t array) =
  let seconds =
    match a.(0) with
    | Int i -> float_of_int i
    | Float x -> x
    | v -> Runtime.fail ctx Type (Messages.need_number "date.Local" (Value.describe v))
  in
  let t = try Unix.localtime seconds with Unix.Unix_error _ -> Unix.gmtime seconds in
  let parts = [| t.tm_year + 1900; t.tm_mon + 1; t.tm_mday; t.tm_hour; t.tm_min; t.tm_sec |] in
  Array { rows = 1; cols = 6; store = I parts; a_owned = true; a_tip = true }

let register ?(max_sleep = infinity) ?tick ?(watching = false) w =
  let poll = Poll.create () in
  w.idle <- Poll.idle poll;
  w.timer <- (fun seconds f -> Poll.timer poll (Float.min max_sleep seconds) f);
  Option.iter (fun (period, f) -> Poll.set_tick poll period f) tick;
  let net = Net.create poll in
  let sys =
    Fs.natives @ Proc.natives poll
    @ [ "Now", Native.nat "Now" 0 0 (fun _ _ -> Float (Unix.gettimeofday ()));
        "Sleep",
        Native.nat "Sleep" 1 1 (fun ctx a ->
            Poll.sleep poll ctx (Float.min max_sleep (Proc.seconds ctx "Sleep" a.(0)));
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
    ("sys", sys) :: ("net", Net.natives net) :: ("c", C.natives (C.create ())) :: ("sqlite3", sqlite_natives) :: ("lapack", Linalg.natives)
    :: ("date", [ "localClock", Native.nat "localClock" 1 1 local_clock ]) :: w.native_modules;
  fun () -> Net.stopping net
