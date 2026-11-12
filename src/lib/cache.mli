(** The loaded form of a package, kept between runs, so that a package unchanged since the last run is not lexed, parsed
    or resolved again. An entry is untrusted bytes: it is decoded only once its digest and what it was made from are
    checked, by a decoder that raises on anything wrong, and any failure only means that the package loads as without it. *)

(** Where entries are kept, which the binary gives: its build, which an entry must name, and how an entry is read and
    replaced by its name, each failing in silence. Without it, nothing is cached. *)
type store = { build : string; read : string -> string option; write : string -> string -> unit }

val store : store option ref

(** Where the entry of a package goes, and what it must match: its sources and the nesting limit. *)
type slot

(** The slot of a package, from its key in the loaded packages and its sources, or [None] when it isn't cached: no build,
    no cache folder, or sources too small to be worth it. A [fixed] source is a text of the binary itself. *)
val slot : key:string -> nesting:int -> fixed:(string -> bool) -> (string * string) list -> slot option

(** The place of a package among the modules: a binding is kept relative to it, as the modules have other numbers in
    another run. [used] is the module of each use of its files, in order; [package] the modules of a module's package. *)
type place = { first : int; count : int; natives : int option; used : int array; package : int -> int array }

(** What a use of a file says: the path, the alias, its place, and the names the file reads from it. *)
type use = { upath : string; ualias : string; upos : Pos.t; unames : string list }

(** An entry that matches its slot, its uses read. *)
type saved

val read : slot -> saved option

(** The uses of each file, in order. *)
val uses : saved -> use list array

(** The questions that resolving a package asked about other modules, with their answers: a name of the package's
    lookup, a name of a package that file [i] uses by an alias, whether a binding is a type. *)
type log

val log : unit -> log
val lookup : log -> (string -> Ast.binding option) -> string -> Ast.binding option
val space : log -> int -> string -> (string -> Ast.binding option) -> string -> Ast.binding option
val is_type : log -> (Ast.binding -> bool) -> Ast.binding -> bool

(** Asks the questions of the entry again: the trees of each file and their layouts, when every answer is the same, else
    [None]. *)
val trees :
  saved -> place -> lookup:(string -> Ast.binding option) -> spaces:(string * (string -> Ast.binding option)) list array ->
  is_type:(Ast.binding -> bool) -> (Ast.func * Ast.layout) list option

(** Saves a package just resolved: its uses, the questions asked and its trees. *)
val write : slot -> place -> log -> use list array -> (Ast.func * Ast.layout) list -> unit
