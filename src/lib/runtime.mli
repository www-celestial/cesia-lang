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
    argument is the top of the v stack still in use: beyond it, everything is dead. The third is the site of the step
    that ran out of fuel, which the limits of steps and of depth name: a loop's, a native's, or a frame's own, its
    function at its line. *)
val checkpoint : ctx -> int -> int -> unit

(** Counts the last steps of a fiber that ends; the limit of steps, reached there, names the site that spawned it. *)
val settle : ctx -> int -> unit

(** Under a limit of steps, takes the steps a fiber about to wait spent since its last checkpoint off what is left, so
    that the others run within what is truly left. *)
val pause : ctx -> unit

(** Gives them back to a fiber that runs again, for its checkpoint to count, and cuts its fuel to the steps the others
    left, or that of a fiber that starts: the limit of steps is then reached at the same step in every fiber,
    interpreted or machine code. *)
val resume : ctx -> unit

(** Counts [n] steps of a native, at its site. *)
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

(** Checks a permission, with the path concerned if any. With [name], the last name of the path is what is acted on, a
    link not followed (removed, renamed, read as a link); with [at], the path is checked where it truly leads, as the system
    holds an open file, and the message names the path. *)
val check_perm : ?name:bool -> ?at:string -> ctx -> perm -> string option -> unit

(** Stops the program on a denied permission, with the path concerned if any, as {!check_perm} does. *)
val deny : ctx -> perm -> string option -> 'a

(** Where a path leads, links resolved, or [None] when no place can be told: set by the system, which reads links. A
    folder of read= or write= holds a path only when it holds where the path leads too. *)
val real_path : (string -> string option) ref

(** The words of an error of the system that a native let out instead of giving an Err, or [None] for another exception:
    a [Sys_error], and those of the calls of the system that src/sys adds. What catches a panic takes it as one of the
    kind io, at the site where it was raised: a native's call, which writes its site before it runs. *)
val stray : (exn -> string option) ref

(** That panic, of such an error raised in [ctx], or [None] for another exception. *)
val stray_panic : ctx -> exn -> exn option

(** Is the permission granted, for this path if any? [name] and [at] as for {!check_perm}. *)
val granted : ?name:bool -> ?at:string -> world -> perm -> string option -> bool

(** Where a path leads, for read= and write=: with [name], its folder resolved and its last name as written, as an act on
    the name itself (a link removed, not what it points to) sees it. *)
val leads : ?name:bool -> string -> string option

(** Does a folder of read= or write= bound this permission, so that a path can be denied? *)
val bounded : world -> perm -> bool

(** a/./b/../c becomes a/c. *)
val normalize : string -> string

(** Is [path] inside [dir]? *)
val inside : string -> string -> bool

(** Does a scope of [--allow] cover this target? *)
val scope_matches : perm -> string -> string -> bool
