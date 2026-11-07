(** [cesia run --workers N]: a supervisor and N processes that serve one listener together. *)

(** The environment variable that makes a [cesia run] a worker, and tells it where its supervisor is. *)
val variable : string

(** Writes the output of a worker in lines that the others' can't cut. *)
val write_lines : string -> unit

(** Starts [count] workers of the command line [argv], gives them [listener] as their standard input, and supervises
    them until they have all ended: it starts again one that ends, stops them on TERM or INT and replaces them on HUP.
    Exits with the first code other than 0 of a worker, or 0. [host] and [port] are those the program asked for, by
    which a worker finds its listener. *)
val supervise : count:int -> argv:string array -> listener:Unix.file_descr -> host:string -> port:int -> 'a
