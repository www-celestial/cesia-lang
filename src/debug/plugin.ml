(* The plugin's entry: loaded at the first call of a native of std/debug that it holds, it gives the binary their code. *)
let () = Cesia_sys.Sys_modules.debugger := Some (Eval.natives, Eval.test, Edit.line)
