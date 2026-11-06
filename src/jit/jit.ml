external load : string -> string array -> nativeint array = "cesia_jit_load"

(* Not [noalloc]: OCaml then writes its young heap's pointer to the domain's state before the call and reads it after,
   so that native code allocates there itself. Nothing in the call collects. *)
external call : nativeint -> int array -> floatarray -> Cesia.Types.t array -> int array -> int = "cesia_jit_call"
