(** Waiting for descriptors: [epoll] on Linux, [select] elsewhere. The rest of [sys/] doesn't know which one runs. *)

type state

(** How many descriptors the backend can watch. *)
val capacity : int

val create : unit -> state

(** Watches a descriptor once, for its whole life. A fiber tries its operation before it waits. *)
val add : state -> Unix.file_descr -> unit

(** Watches a listening socket, which other processes may watch too: a new connection wakes one of them, not all. *)
val add_listener : state -> Unix.file_descr -> unit

val remove : state -> Unix.file_descr -> unit

(** Waits at most [timeout] seconds, for ever if negative, and returns the descriptors that may be ready. The function
    gives the descriptors waited on, for reading and for writing: [select] needs them, [epoll] doesn't. *)
val wait :
  state -> float -> (unit -> Unix.file_descr list * Unix.file_descr list) -> Unix.file_descr list
