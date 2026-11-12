(** The world of a program and the context of a fiber. *)
open Types

type options = {
  o_limits : limits;
  o_grants : grants;
  o_no_spec : bool;
  o_debugger : string option;
  o_repl : bool;  (** cesia run --repl *)
  o_cells : bool;  (** cesia run --cells *)
  o_period : int;
  o_sink : string -> unit;
  o_err : string -> unit;
}

val default_limits : limits

(** The default memory limit, in words, from the size of the RAM in bytes: 80% of it, or [max_int] if the size is 0. *)
val default_memory : int -> int
val default_options : options
val create_world : options -> world
(** A new context, with stacks of [stack] entries that grow on demand. *)
val create_ctx : ?stack:int -> ?fiber:bool -> ?id:int -> world -> ctx

(** Flushes the output buffer to [world.sink]. *)
val flush_out : world -> unit

(** The number of frames, following the links. *)
val frames : ctx -> int

(** The caller's base, read from a frame link. *)
val link_base : int -> int

(** Raises a Cesia error at the current site. *)
val fail : ctx -> kind -> Messages.t -> 'a

(** The young heap grown to 16 MB, once: at the first checkpoint, or once a program loaded 32 KB of source. *)
val grow_young : unit -> unit

(** The checkpoint: refills [fuel], flushes the output, looks at the memory, calls [on_checkpoint]. The second
    argument is the top of the v stack still in use: beyond it, everything is dead. *)
val checkpoint : ctx -> int -> unit

(** Counts [n] steps. *)
val settle : ctx -> unit
(** Counts the last steps of a fiber that ends. *)

val charge : ctx -> int -> unit

(** Steps for work over [n] cells. *)
val pay : ctx -> int -> unit

(** Steps for work over [n] bytes: what grows with a text pays at this rate. *)
val pay_bytes : ctx -> int -> unit

(** Grows the three stacks to hold [need] entries. *)
val grow : ctx -> int -> unit

(** The stack lines of an error raised at site [at], most recent first. *)
(** The site an error shows first: where it was raised, or the line of the program that called into a library of [std/]
    or [deps/] where it was raised. *)
val user_site : ctx -> int -> int

val backtrace : ?above:int -> ctx -> int -> string list

(** Checks two dimensions and returns their product. *)
val cells : ctx -> int -> int -> int

(** Shallow copy, [owned], which clears [owned] on the direct elements. *)
val copy : ctx -> t -> t

(** The value if it is [owned], else a copy. *)
val own : ctx -> t -> t

(** To call before allocating n words. [ctx.site] must be up to date: it bounds the stack. *)
val reserve : ctx -> int -> unit

(** Stops the program on this limit. *)
val limit : string -> int -> 'a

(** Before building n elements: counts the steps and reserves the memory. *)
val build : ctx -> int -> unit

val alloc_float : ctx -> int -> float -> floatarray
val alloc_vals : ctx -> int -> t -> t array
val alloc_ints : ctx -> int -> int -> int array

(** Checks a permission, with the path concerned if any. *)
val check_perm : ctx -> perm -> string option -> unit

(** Where a path leads, links resolved, or [None] when no place can be told: set by the system, which reads links. A
    folder of read= or write= holds a path only when it holds where the path leads too. *)
val real_path : (string -> string option) ref

(** Is the permission granted, for this path if any? *)
val granted : world -> perm -> string option -> bool

(** a/./b/../c becomes a/c. *)
val normalize : string -> string

(** Is [path] inside [dir]? *)
val inside : string -> string -> bool

(** Does a scope of [--allow] cover this target? *)
val scope_matches : perm -> string -> string -> bool
