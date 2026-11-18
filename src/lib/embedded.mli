(** The files of std/ and tools/, embedded by gen/gen_embed.ml. A file is the same string at every call, and costs nothing
    at start-up: no data of the binary points to it. *)

(** The files of std/: their names, without extension. *)
val names : string list

(** [file name]: the source of std/[name].ce. *)
val file : string -> string option

(** Whether [src] is one of the files of std/ itself, the very string [file] gives. *)
val holds : string -> bool

(** The tools, which the binary runs for [cesia pkg] and [cesia upgrade], and [--debugger debugger]: never a library. Their
    names, without extension. *)
val tools : string list

(** [tool name]: the source of the tool [name]. *)
val tool : string -> string option

(** [asset name]: a tool's other file, by name with extension: [site.css] and [site.js], the look of [cesia doc --site]. *)
val asset : string -> string option
