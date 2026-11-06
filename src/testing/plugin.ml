(* The plugin's entry: loaded by the binary for cesia test, it gives the binary the runner. *)
let () =
  Testing.runner := Some { run = Testrun.run; units = Testrun.unit_paths; tick = Testrun.tick; reset = Testrun.reset }
