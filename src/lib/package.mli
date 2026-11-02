(** A package is a folder: where a project starts, and which files a folder holds. *)

(** The name of the file that marks the root of a project. *)
val project_file : string

(** The end of the name of a Kepler source: [.k]. *)
val suffix : string

val is_source : string -> bool

(** A test ends in [.test.k], and is a source too. *)
val is_test : string -> bool

val is_dir : string -> bool

(** The code of a package, in the order of the names: the [.k] files of the folder, without its subfolders, its [.test.k]
    files and its dot files. A folder that doesn't exist has none. *)
val files : string -> string list

(** The same path from the top of the file system. *)
val absolute : string -> string

(** The folder of the nearest {!project_file} above this file or folder, or else the folder itself. *)
val root_of : string -> string

(** The folder a use names in a project: in the [src] folder of the root if it is there, or else from the root, where [tests]
    and [examples] are. *)
val folder : string -> string -> string

(** A path as a person reads it: from the working directory when it is under it. *)
val shown : string -> string
