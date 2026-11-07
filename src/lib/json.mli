(** The json module: reads hostile text into values, and writes values as text. *)
open Types

val natives : (string * t) list

(** The JSON text of a value, as json.Text gives it: std/log writes its fields with it. *)
val text : ctx -> t -> string
