(** The [c] module: calling C libraries from Cesia. A granted library is total trust. Without one, a program can't reach
    any memory outside its own blocks. *)

type t

val create : unit -> t

(** Forgets the fibers waiting to make a slow call: a test ended, and its fibers with it. *)
val reset : unit -> unit
val natives : t -> (string * Cesia.Types.t) list

(** The same file names in the lib/ of a release, beside the bin/ that holds the running binary, links followed; none outside
    a release. A path is never one of them. *)
val in_release : string list -> string list

(** The files to try for a library's short name and version, in order: the release's own first. *)
val candidates : string -> string option -> string list

(** [call_ints address args]: the int that the C function at [address] gives for up to 6 int arguments; for a function
    of no result, what its register holds. *)
val call_ints : int -> int array -> int
