type t = { text : string; hint : string option }

let plain text = { text; hint = None }
let hinted text hint = { text; hint = Some hint }

let fits = "Integers have 63 bits. To go further, use a float: 1.0 * x."
let invalid_utf8 = plain "This file is not valid UTF-8."
let unexpected_char c = plain (Printf.sprintf "Unexpected character %C." c)
let text_not_closed = plain "This text is not closed: a closing \" is missing."
let number_too_big s = hinted (Printf.sprintf "The number %s doesn't fit in 63 bits." s) (Printf.sprintf "Write it as a float: %s.0." s)
let expected what got = plain (Printf.sprintf "Expected %s, found %s." what got)
let too_nested = plain "This code is nested too deeply."
let cant_assign = plain "Only a variable can be assigned here."
let break_outside = plain "break can only be used inside a loop."
let undefined name = plain (Printf.sprintf "Name \"%s\" doesn't exist." name)
let unset name = hinted (Printf.sprintf "\"%s\" has no value yet." name) "Give it a value before reading it."

let text_hint = "To put a value in a text, write \"...$x\" or text(x)."

let binary verb a joiner b is_text =
  let text = Printf.sprintf "Can't %s %s %s %s." verb a joiner b in
  if is_text then hinted text text_hint else plain text

let overflow a op b = hinted (Printf.sprintf "The integer result of %s %s %s doesn't fit in 63 bits." a op b) fits
let overflow_neg a = hinted (Printf.sprintf "The integer result of -(%s) doesn't fit in 63 bits." a) fits
let div_zero name = plain (Printf.sprintf "%s: division by zero." name)
let negate a = plain (Printf.sprintf "Can't take the opposite of %s." a)
let compare_op a op b = plain (Printf.sprintf "Can't compare %s %s %s." a op b)
let condition a = plain (Printf.sprintf "A condition must be true or false, not %s." a)
let not_function a = plain (Printf.sprintf "Can't call %s: it is not a function." a)
let arg_count name want got = plain (Printf.sprintf "%s takes %s, not %d." name want got)
let want_int name a = plain (Printf.sprintf "%s needs a whole number, not %s." name a)
let limit what = plain (Printf.sprintf "Limit \"%s\" reached." what)
let too_many fname want got = plain (Printf.sprintf "%s takes %d arguments, not %d." fname want got)
let missing_arg fname param = plain (Printf.sprintf "%s needs the argument \"%s\"." fname param)
let unknown_arg fname name = plain (Printf.sprintf "%s has no argument named \"%s\"." fname name)
let duplicate_arg fname name = plain (Printf.sprintf "%s received the argument \"%s\" twice." fname name)
let duplicate name = plain (Printf.sprintf "The function \"%s\" is defined twice." name)
let assign_function name = plain (Printf.sprintf "\"%s\" is a function of this file and can't be assigned." name)
let return_outside = plain "return can only be used inside a function."
let whole_hint = "To get a whole number, use floor(...), ceil(...) or round(...)."
let range_bound a = hinted (Printf.sprintf "A range needs whole numbers, not %s." a) whole_hint
let index_type a = hinted (Printf.sprintf "An index must be a whole number, not %s." a) whole_hint
let index_outside i n = plain (Printf.sprintf "Index %d is outside this array of %d elements." i n)
let index_outside2 i j r c = plain (Printf.sprintf "Index [%d, %d] is outside this array of %d rows and %d columns." i j r c)
let index_write = plain "Only one element can be written at a time."
let index_value a = plain (Printf.sprintf "Can't index %s." a)
let mask_size got want = plain (Printf.sprintf "This mask has %d elements, the array has %d." got want)
let cant_loop a = plain (Printf.sprintf "Can't loop over %s." a)
let cant_in a = plain (Printf.sprintf "Can't look inside %s with \"in\"." a)
let rows_differ = plain "The rows of this array have different lengths."
let bad_size name a = plain (Printf.sprintf "%s needs a size, not %s." name a)
let reshape_size n r c = plain (Printf.sprintf "Can't reshape %d elements into %d rows and %d columns." n r c)
let size_dim a = plain (Printf.sprintf "size's dimension must be 1 or 2, not %s." a)
let shape a b c d = plain (Printf.sprintf "Can't combine an array of %d by %d with an array of %d by %d." a b c d)
let matmul_shape a b c d =
  plain (Printf.sprintf "matmul can't multiply %d by %d with %d by %d: the columns of the first must equal the rows of the second." a b c d)
let need_number name a =
  let text = Printf.sprintf "%s needs numbers, not %s." name a in
  if a = "function <anonymous>" then hinted text "\"it\" belongs to the nearest call. Write x -> ... to use it further out."
  else plain text
let it_assign = plain "\"it\" is a reserved name and can't be assigned."
let no_field name = plain (Printf.sprintf "This struct has no field \"%s\"." name)
let named_field sname name = plain (Printf.sprintf "%s has no field \"%s\"." sname name)
let field_of a name = plain (Printf.sprintf "Can't read the field \"%s\" of %s." name a)
let struct_nested = plain "A struct can only be defined at the top of a file."
let destructure_array want got = plain (Printf.sprintf "This pattern takes %d elements, the value has %d." want got)
let destructure_struct a = plain (Printf.sprintf "This pattern needs a struct, not %s." a)
let destructure_value a = plain (Printf.sprintf "This pattern needs an array, not %s." a)
let index_count = plain "An array has 2 dimensions: use one or two indexes."
let range_too_long = plain "This range has too many elements."
let no_on_stop = plain "The debugger has no function on_stop(stop)."
let bad_answer a =
  plain (Printf.sprintf "on_stop must return \"continue\", \"step\", \"next\" or \"out\", not %s." a)
let need_text name a = plain (Printf.sprintf "%s needs a text, not %s." name a)
let empty_array name = plain (name ^ " of an empty array.")
let usage =
  "usage: kepler run [--allow LIST] [--limit LIST] [--watch] [--debugger FILE] [--no-spec] file.kp [args...]\n\
  \       kepler test [path] [--no-spec]\n\
  \       kepler version"
let cant_read path = "can't read " ^ path
let unknown_permission name = "unknown permission: " ^ name
let invalid_permission item = "invalid permission: " ^ item
let invalid_size s = "invalid size: " ^ s
let invalid_limit s = "invalid limit: " ^ s
let unknown_limit name = "unknown limit: " ^ name
let internal e = "Internal error: " ^ e
let no_match a = plain (Printf.sprintf "No branch of this match accepts %s." a)
let assertion = plain "Assertion failed."
let use_nested = plain "use can only be used at the top of a file."
let use_cycle = plain "This use creates a cycle between modules."
let use_unreadable path = plain (Printf.sprintf "Can't read the module \"%s\"." path)
let no_prelude = plain "The folder of KEPLER_STD has no prelude.kp."
let reload_use = plain "A running program can't load a new module. Restart it to use this one."
let use_missing path = plain (Printf.sprintf "Module \"%s\" doesn't exist." path)
let no_name alias name = plain (Printf.sprintf "Module \"%s\" has no name \"%s\"." alias name)
let denied perm = plain (Printf.sprintf "Permission \"%s\" denied. Run again with --allow %s." perm perm)
