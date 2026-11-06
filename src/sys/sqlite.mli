(** The [sqlite3] module: the C side of SQLite, called from OCaml so that a batch of rows costs Cesia one call. Connections
    open with safe settings; statements are cached by text; rows come by batches as flat cells. [pkg/sqlite] builds on it. *)

val natives : (string * Cesia.Types.t) list
