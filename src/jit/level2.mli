(** A unit's level 2: MIR's machine code at its level 2, slower to make and faster to run, made by another domain from
    the unit's MIR text while the unit runs its level 1. One at a time. *)

(** Where a level 2 stands: being made, made (the context, then the entry's address), refused by MIR or by a domain
    that couldn't start, or abandoned by a unit that died first. *)
type state = Working | Made of nativeint array | Refused | Abandoned

(** [start ~wait text entry]: a level 2 being made, or [None] while another one is. With [wait], as under
    [CESIA_JIT=always], it is made before [start] returns. *)
val start : wait:bool -> string -> string -> state Atomic.t option

(** For a unit that died before it took its level 2: the context goes, now if it is made, or when it is. *)
val drop : state Atomic.t -> unit

(** Is a level 2 being made. *)
val busy : unit -> bool
