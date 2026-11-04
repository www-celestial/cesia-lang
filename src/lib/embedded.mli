(** The files of std/ and tools/, embedded by gen/gen_embed.ml: name without extension, source. *)

val files : (string * string) list

(** The tools, which the binary runs for [cesia pkg] and [cesia upgrade], and [--debugger debugger]: never a library. *)
val tools : (string * string) list
