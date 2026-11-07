(** The interface of native packages, version 1: what the OCaml code of a package's engine may call. Frozen once
    released: this file never changes then, not even a comment, since OCaml's check of a plugin covers its every byte, and
    what comes later goes in new modules, Cesia_v1_1 and on. An engine is compiled against the .cmi of this file alone.

    Every function runs on Cesia's domain, the main one, but the [resume] of [suspend]. Between two calls, a package keeps
    OCaml data, never a value: Cesia changes in place a list, a map or a struct that nothing else holds. *)

type value
(** A value of the program. Its layout is Cesia's own and changes between releases: a package makes and reads values only
    through the functions below. *)

type ctx
(** The fiber that called a native. *)

type keys
(** The field names of the maps that [record] makes: made once, at the engine's start, and shared by every map made with
    them. *)

(** {1 Making values} *)

val missing : value
val bool : bool -> value
val int : int -> value
val float : float -> value

val text : string -> value
(** A text, UTF-8 as every text of Cesia: the string is not copied. *)

val list : ctx -> value array -> value
(** A list of these values, counted for --limit memory: the array is the list's own from now on. *)

val keys : string array -> keys

val record : ctx -> keys -> value array -> value
(** A map with a value for each name of [keys], in their order, counted for --limit memory: the array is the map's own from
    now on. *)

val handle : string -> int -> value
(** A reference to something the package keeps: its kind, named after the package as "cepheus.database", and its
    number. *)

val ok : ctx -> value -> value

val err : ctx -> value -> value
(** result.Ok and result.Err of a value. *)

(** {1 Reading values} *)

(** What a value is. [List]: a list, an array of one dimension. [Other]: anything else, as a matrix, and whatever later
    releases add. *)
type kind = Missing | Bool | Int | Float | Text | List | Map | Struct | Function | Handle | Other

val kind : value -> kind

val to_bool : ctx -> string -> value -> bool
(** The value, or a panic that names the native and says what it got: [to_bool ctx "cepheus.Open" v]. *)

val to_int : ctx -> string -> value -> int

val to_float : ctx -> string -> value -> float
(** An Int is taken as a Float. *)

val to_text : ctx -> string -> value -> string

val length : value -> int
(** The items of a list, the fields of a map or a struct; 0 for anything else. *)

val item : ctx -> value -> int -> value
(** An item of a list, from 0, or a panic. *)

val field : value -> string -> value
(** A field of a map or a struct, or missing. *)

val names : value -> string array

val values : value -> value array
(** The field names of a struct, or the keys of a map that are texts, in order; and their values, in the same order. *)

val handle_id : ctx -> string -> string -> value -> int
(** The number of a handle of this kind, or a panic: [handle_id ctx "cepheus.Get" "cepheus.database" v]. *)

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
