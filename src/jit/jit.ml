external load_c : string -> string array -> int -> nativeint array = "cesia_jit_load"
external free_c : nativeint -> unit = "cesia_jit_free"

let alive = Atomic.make 0

let load text names level =
  let a = load_c text names level in
  Atomic.incr alive;
  a

let free c =
  free_c c;
  Atomic.decr alive

let live () = Atomic.get alive

(* Not [noalloc]: OCaml then writes its young heap's pointer to the domain's state before the call and reads it after,
   so that native code allocates there itself. Nothing in the call collects. *)
external call : nativeint -> int array -> floatarray -> Cesia.Types.t array -> int array -> int = "cesia_jit_call"
