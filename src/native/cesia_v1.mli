(** The interface of native packages, version 1: what the OCaml code of a package's engine may call. Frozen once
    released: this file never changes then, not even a comment, since OCaml's check of a plugin covers its every byte, and
    what comes later goes in new modules, Cesia_v1_1 and on. An engine is compiled against the .cmi of this file alone.

    Every function runs on Cesia's domain, the main one, but the [resume] of [suspend]. Between two calls, a package keeps
    OCaml data, never a value: Cesia changes in place a list, a map or a struct that nothing else holds. *)

type ctx
(** The fiber that called a native. *)

type keys
(** The field names of the maps that [record] makes and of the fields that [fields] reads: made once, at the engine's
    start, their hashes computed then. *)

type compound
(** A value that holds others, or that a package can't take apart: its layout is Cesia's own and changes between releases,
    so a package reads it only through the functions below. *)

(** A value of the program, as a native takes and gives it: the simple ones as OCaml's own, so that a package makes and
    reads them without a call to Cesia, the others as a [compound]. *)
type value =
  | Missing
  | Bool of bool
  | Int of int
  | Float of float
  | Text of string  (** UTF-8, as every text of Cesia: the string is not copied *)
  | Handle of string * int
      (** a reference to something the package keeps: its kind, named after the package as "cepheus.database", and its
          number *)
  | List of compound  (** a list, an array of one dimension *)
  | Map of compound
  | Struct of compound
  | Function of compound
  | Other of compound  (** anything else, as a matrix, and whatever later releases add *)

(** {1 Making values} *)

val list : ctx -> value array -> value
(** A list of these values, counted for --limit memory. *)

val keys : string array -> keys

val record : ctx -> keys -> value array -> value
(** A map with a value for each name of [keys], in their order, counted for --limit memory. *)

val ok : ctx -> value -> value

val err : ctx -> value -> value
(** result.Ok and result.Err of a value. *)

(** {1 Reading values} *)

val length : compound -> int
(** The items of a list, the fields of a map or a struct; 0 for anything else. *)

val item : ctx -> compound -> int -> value
(** An item of a list, from 0, or a panic. *)

val fields : keys -> compound -> value array
(** The fields of a map or a struct with the names of [keys], in their order: Missing for a name it doesn't have. *)

val names : compound -> string array

val values : compound -> value array
(** The field names of a struct, or the keys of a map that are texts, in order; and their values, in the same order. *)

val need : ctx -> string -> string -> value -> 'a
(** A panic that names the native, what it needs and what it got: [need ctx "cepheus.Get" "an Int" v] stops the fiber with
    "cepheus.Get needs an Int, not the text "a".". *)

(** {1 Waiting} *)

val suspend : ctx -> ((unit -> unit) -> unit) -> unit
(** Parks the calling fiber and calls the function with [resume]: the other fibers run until [resume] is called, once, from
    any domain; a second call does nothing. If the fiber is cancelled meanwhile, [suspend] raises, and the late [resume]
    does nothing. *)

(** {1 Permissions, bugs and limits} *)

val need_read : ctx -> string -> unit

val need_write : ctx -> string -> unit
(** A panic, as for sys.Read and sys.Write, unless the program may read or write this path. *)

val panic : ctx -> string -> 'a
(** Stops the fiber with this message, as bug.Panic does. Any other OCaml exception that leaves a native becomes a panic
    too; the package never catches the exceptions that these functions raise. *)

val pay : ctx -> int -> unit
(** Counts a walk over this many values, for --limit steps. *)

val reserve : ctx -> int -> unit
(** Counts words of memory that the package holds for the program, for --limit memory. *)

(** {1 The natives} *)

val register : (string * int * int * (ctx -> value array -> value)) list -> unit
(** The natives of the package, by the names its cesia.toml lists: name, fewest and most arguments, code. Called once, by
    the engine's start. *)
