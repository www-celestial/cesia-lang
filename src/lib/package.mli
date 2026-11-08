(** A package is a folder: where a project starts, and which files a folder holds. *)

(** The name of the file that marks the root of a project. *)
val project_file : string

(** The end of the name of a Cesia source: [.ce]. *)
val suffix : string

val is_source : string -> bool

(** A test ends in [.test.ce], and is a source too. *)
val is_test : string -> bool

val is_dir : string -> bool

(** A file of Cesia's std/ that the binary holds, as [std/list.ce]: no reload changes it, unless CESIA_STD is set. *)
val embedded_std : string -> bool

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

(** The [native] of a project: its [project] name, the folder of the package whose files see the natives of its engine,
    from the top of the file system, and their names. Read with [sources]. *)
type native = { name : string; package : string; natives : string list }

val native : string -> native option

(** [use deps/someone/geometry/shapes] names a package of another project: [Some ("deps/someone/geometry",
    "shapes")]. A first part with a dot is a host: [deps/gitlab.com/x/y/z] gives [Some ("deps/gitlab.com/x/y", "z")]. *)
val dep : string -> (string * string) option

(** The folder a use names in a project: in the first source folder of the root that holds it, or else from the root, where
    [tests] and [examples] are. *)
val folder : string -> string -> string

(** A path as a person reads it: from the working directory when it is under it. *)
val shown : string -> string

(** [blake2:] and the 64 hexadecimal digits of the BLAKE2b-256 of a text: what cesia.lock keeps of a file. *)
val fingerprint : string -> string

(** The fingerprints that the cesia.lock of a root gives the files of its std/ and deps/, by absolute path; none without one.
    Read once per root. *)
val lock : string -> (string, string) Hashtbl.t

(** The label of the [deps] table of a root's cesia.lock whose files are in this folder of deps/: [label root
    "deps/someone/geometry"]. *)
val label : string -> string -> string option

(** Why a file of std/ or deps/ isn't as installed, from its text: changed by hand, or not installed; [None] when it is, or
    when it is a file of the project itself. *)
val unchanged : string -> string -> string -> Messages.t option

(** [installed root path]: the folder of std/ or deps/ that holds a file, from the root ([std/csv],
    [deps/someone/geometry], [deps/gitlab.com/x/y]), or [None] for a file of the project itself. *)
val installed : string -> string -> string option
