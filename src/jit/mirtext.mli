(** The IR as MIR text, for the backend that makes machine code of it, [Tier.backend], which [src/sys] sets. *)

(** The MIR text of a unit, whose function 0 the others serve, the name of its single entry, and the sites that a limit
    of steps names at its ticks, which native code doesn't write: each a site in the world, or -1 for the call that made
    the frame. *)
type text = {
  text : string;
  entry : string;
  points : int array;  (** at each resume point of function 0, the site of the tick that leaves there *)
  ticks : int array array;
      (** for each number that a tick stops with at the limit of steps, in [Ir.io_code], the sites of its steps, in order:
          several when [Ir.Steps] folded them *)
  entries : (int, int) Hashtbl.t;
      (** for each site of a call where the limit of depth can stop, which [Ir.io_point] gives, the site of the entry
          of the frame it enters, which that limit names *)
}

val emit : Ir.func array -> text
