(** The world of a program and the context of a fiber. *)
open Types

type options = {
  o_limits : limits;
  o_grants : grants;
  o_no_spec : bool;
  o_debugger : string option;
  o_period : int;
  o_sink : string -> unit;
  o_err : string -> unit;
}

val default_limits : limits
val default_options : options
val create_world : options -> world
val create_ctx : world -> ctx

(** Flushes the output buffer to [world.sink]. *)
val flush_out : world -> unit

(** The number of frames, following the links. *)
val frames : ctx -> int

(** The caller's base, read from a frame link. *)
val link_base : int -> int

(** Raises a Kepler error at the current site. *)
val fail : ctx -> kind -> Messages.t -> 'a

(** The checkpoint: refills [fuel], flushes the output, looks at the memory, calls [on_checkpoint]. The second
    argument is the top of the v stack still in use: beyond it, everything is dead. *)
val checkpoint : ctx -> int -> unit

(** Counts [n] steps. *)
val charge : ctx -> int -> unit

(** Grows the three stacks to hold [need] entries. *)
val grow : ctx -> int -> unit

(** The stack lines of an error raised at site [at], most recent first. *)
val backtrace : ctx -> int -> string list

(** Checks two dimensions and returns their product. *)
val cells : ctx -> int -> int -> int

(** Shallow copy, [owned], which clears [owned] on the direct elements. *)
val copy : ctx -> t -> t

(** The value if it is [owned], else a copy. *)
val own : ctx -> t -> t

(** To call before allocating n words. [ctx.site] must be up to date: it bounds the stack. *)
val reserve : ctx -> int -> unit

(** Before building n elements: counts the steps and reserves the memory. *)
val build : ctx -> int -> unit

val alloc_float : ctx -> int -> float -> floatarray
val alloc_vals : ctx -> int -> t -> t array

(** Checks a permission, with the path concerned if any. *)
val check_perm : ctx -> perm -> string option -> unit

(** Is the permission granted, for this path if any? *)
val granted : world -> perm -> string option -> bool

(** a/./b/../c becomes a/c. *)
val normalize : string -> string

(** Is [path] inside [dir]? *)
val inside : string -> string -> bool
