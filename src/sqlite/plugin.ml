(* The plugin's entry: loaded by the binary at the first call of sqlite3, it gives the binary the natives' code. *)
let () = Cesia_sys.Sys_modules.sqlite3 := Sqlite.natives
