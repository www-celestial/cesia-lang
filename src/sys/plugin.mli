(** Loads a native plugin (.cmxs) as OCaml's Dynlink does, without the cost of linking Dynlink: checks that the plugin was
    built against this program's interfaces and implementations, and those of the plugins loaded before, then runs its
    modules. [global]: later plugins may call its code, as engines call Cesia_v1. [strict]: the engine of a native package,
    which may see no interface of Cesia but Cesia_v1, nor bring a module named as Cesia's, and whose every implementation
    must be here. [Error] says why it didn't load; nothing of the plugin ran then. *)
val load : ?global:bool -> ?strict:bool -> string -> (unit, string) result
