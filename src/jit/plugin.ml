(* The plugin's entry: loaded by the binary at the first hot unit, it gives the interpreter its JIT. *)
let () = Engine.install ()
