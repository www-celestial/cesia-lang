(** A unit's level 2: MIR's machine code at its level 2, slower to make and faster to run, made by another domain from
    the unit's MIR text while the unit runs its level 1. One at a time. *)

(** Where a level 2 stands: being made, made (the context, then the entry's address), or refused, by MIR or by a domain
    that couldn't start. *)
type state = Working | Made of nativeint array | Refused

(** [start ~wait text entry]: a level 2 being made, or [None] while another one is. With [wait], as under
    [CESIA_JIT=always], it is made before [start] returns. *)
val start : wait:bool -> string -> string -> state Atomic.t option

(** Is a level 2 being made. *)
val busy : unit -> bool
