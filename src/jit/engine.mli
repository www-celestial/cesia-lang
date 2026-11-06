(** The JIT's tier: versions and loops that get hot run as native code, made by [Lower] and [Mirtext], with the same
    output, errors and limits as the interpreter. *)

(** Fills [Tier.jit]: the plugin does at its load, tests and the fuzzer, which link the JIT, when they want it. *)
val install : unit -> unit
