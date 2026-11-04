(** A package is a folder: where a project starts, and which files a folder holds. *)

(** The name of the file that marks the root of a project. *)
val project_file : string

(** The end of the name of a Cesia source: [.ce]. *)
val suffix : string

val is_source : string -> bool

(** A test ends in [.test.ce], and is a source too. *)
val is_test : string -> bool

val is_dir : string -> bool

(** The code of a package, in the order of the names: the [.ce] files of the folder, without its subfolders, its [.test.ce]
    files and its dot files. A folder that doesn't exist has none. *)
val files : string -> string list

(** The same path from the top of the file system. *)
val absolute : string -> string

(** The folder of the nearest {!project_file} above this file or folder, or else the folder itself. *)
val root_of : string -> string

(** [cesia = "0.3"] in [project] asks for a newer Cesia, or holds no version: its line and why. The first thing read in a
    cesia.toml, so that an older Cesia says so before it finds a field it doesn't know. *)
val wrong_cesia : Toml.table list -> (int * Messages.t) option

(** The source folders of a root: [project] src of its cesia.toml, or else [["src"]]. Read once per root; a wrong one raises
    {!Pos.Load_error} at its line. *)
val sources : string -> string list

(** [use pkg/rope] names a library: [Some "rope"], the name after [pkg/] when nothing follows it. *)
val library : string -> string option

(** The folder a use names in a project: in the first source folder of the root that holds it, or else from the root, where
    [tests] and [examples] are. *)
val folder : string -> string -> string

(** A path as a person reads it: from the working directory when it is under it. *)
val shown : string -> string
