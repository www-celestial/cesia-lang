(** The checks of [cesia check] that read a resolved file without running it: the arguments of a call to a known function,
    struct or native, the types of the values given to a typed parameter or field or that a typed function ends with, a result
    used as a plain value or dropped, and the [!] that a typed function giving an Err lacks. *)

(** [file w ~host fn add] checks a resolved file whose module has [host] as the first module of its package. [add pos warning
    message] gets each finding: an error where the program would surely fail, a warning otherwise. *)
val file : Types.world -> host:int -> Ast.func -> (Pos.t -> bool -> Messages.t -> unit) -> unit
