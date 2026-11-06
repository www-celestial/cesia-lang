(** Loads a native plugin (.cmxs) as OCaml's Dynlink does, without the cost of linking Dynlink: checks that the plugin was
    built against this program's interfaces and implementations, then runs its modules. [Error] says why it didn't load;
    nothing of the plugin ran then. *)
val load : string -> (unit, string) result
