open Types

type backend = {
  load : string -> string array -> nativeint array;
  call : nativeint -> int array -> floatarray -> t array -> int array -> int;
}

let backend : backend option ref = ref None
