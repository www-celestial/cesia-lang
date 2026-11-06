(** The IR as MIR text, for the backend that makes machine code of it, [Tier.backend], which [src/sys] sets. *)

(** The MIR text of a unit, whose function 0 the others serve, and the name of its single entry. *)
val emit : Ir.func array -> string * string
