(** The line editor of debug.ReadLine on a terminal, in the plugin of the debugger's engine: arrows, Home, End, Ctrl-A,
    Ctrl-E, Ctrl-K, Ctrl-U, Ctrl-W, and up and down for the lines read before. *)

(** [line prompt byte]: a line edited after the prompt, the bytes of the input coming from [byte]; [None] at its end. *)
val line : string -> (unit -> char option) -> string option
