(** The dense output of std/ode, as its private natives [states], the state at many times of a Solution in one walk of
    its steps, and [stateIn], the state at one time inside one step, for the events. *)

val natives : (string * Types.t) list
