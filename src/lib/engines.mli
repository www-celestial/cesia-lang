(** Native packages: the natives of the package that the [native] of a cesia.toml names, as stubs, which the plugin of
    Cesia_v1 links to its engine at the first call of one of them. *)
open Types

(** Set by the binary: the tag of the engines it loads, as 1-ocaml5.5.0+fp-linux-x86_64, and how it loads the plugin of
    Cesia_v1, once. *)
val suffix : (unit -> string) ref

val interface : (unit -> (unit, string) result) ref

(** Set by the plugin of Cesia_v1: the engine of a package, checked and loaded, or a panic; its natives by name, each with
    the count of its arguments checked. [link ctx ~label ~folder ~path p]: [label] names its permission, [folder] its
    folder of deps/, or "" for the project's own, and [path] its file. *)
val link : (ctx -> label:string -> folder:string -> path:string -> Package.native -> (string * (ctx -> t array -> t)) list) ref

(** The stubs of the natives of the package in this folder, from the top of the file system, if a [native] names it. *)
val natives : world -> string -> (string * t) list option

(** [cesia.Native]: the tag of the engines this Cesia loads. *)
val cesia : (string * t) list
