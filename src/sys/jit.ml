external load : string -> string array -> nativeint array = "cesia_jit_load"

external call : nativeint -> int array -> floatarray -> Cesia.Types.t array -> int array -> int = "cesia_jit_call"
[@@noalloc]

let install () = Cesia.Mirtext.backend := Some { load; call }
