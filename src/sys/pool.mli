(** The domains that run the slow calls of C and the lookups of names, each kept a while once done. *)

(** [run work finish]: [work] on a domain of the pool, then [finish] once that domain is free for the next; false when no
    domain can start. Neither raises. *)
val run : (unit -> unit) -> (unit -> unit) -> bool

(** Sends every idle domain away and waits for its end: before a fork, which OCaml refuses while another domain runs. *)
val stop : unit -> unit
