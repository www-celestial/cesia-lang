(** The version of this Cesia, and how versions compare. *)

(** The name and version shown by [cesia version]: [cesia 0.2.0+dev] when built from the sources. *)
val text : string

(** The version alone: [0.2.0]. *)
val number : string

(** Built from the sources, not by a release: {!text} ends in [+dev]. *)
val dev : bool

(** A version is numbers between dots, after an optional [v]: [0.2], [v1.10.0]. *)
val valid : string -> bool

(** Compares two versions number by number: a leading [v] and what follows a [+] or a [-] are left out, and a missing number
    is 0, so [0.2] is [0.2.0] and [0.10] comes after [0.9]. *)
val compare : string -> string -> int

(** This Cesia is that version or a later one. *)
val at_least : string -> bool
