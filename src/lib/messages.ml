type t = { text : string; hint : string option }

let plain text = { text; hint = None }

let at ~file ~line ~col text = Printf.sprintf "%s:%d:%d: %s" file line col text
let hinted text hint = { text; hint = Some hint }

let fits = "Integers have 63 bits. To go further, use a float: 1.0 * x."
let invalid_utf8 = plain "This file is not valid UTF-8."
let unexpected_char c = plain (Printf.sprintf "Unexpected character %C." c)
let text_not_closed = plain "This text is not closed: a closing \" is missing."
let text_doubled_quote = hinted "Two quotes in a row end a text and start another." "A quote inside a text is written \\\": \"say \\\"hi\\\"\"."
let comment_not_closed = plain "This comment is not closed: a closing *) is missing."
let comment_dashes = plain "Comments are written (* ... *)."
let arrow_outside =
  hinted "--> shows a value only in an example: in a documentation comment (** *), or in a book."
    "In a program, io.Print(x) prints it."
let number_too_big s = hinted (Printf.sprintf "The number %s doesn't fit in 63 bits." s) (Printf.sprintf "Write it as a float: %s.0." s)
let expected what got = plain (Printf.sprintf "Expected %s, found %s." what got)
let too_nested = plain "This code is nested too deeply."
let colon_range = plain "A range is written with two dots, as in 1..n, which is list.Range(1, n), and a method is reached with one dot."
let cant_assign = plain "Only a variable can be assigned here."
let break_outside = plain "break can only be used inside a loop."
let underscore_name name small capital =
  let text = Printf.sprintf "A name can't hold a _: \"%s\"." name in
  if small = "" then plain text
  else hinted text (Printf.sprintf "Join the words with capitals: %s, or %s when it is public." small capital)
let private_member name =
  hinted (Printf.sprintf "The field or method \"%s\" is private to the package that declares it." name)
    "A field or a method is public when its first letter is a capital."
let undefined name = plain (Printf.sprintf "Name \"%s\" doesn't exist." name)
let package_unused name =
  hinted (Printf.sprintf "Name \"%s\" doesn't exist." name) (Printf.sprintf "%s is a package of std/: write use std/%s first." name name)
let moved name p = plain (Printf.sprintf "%s is in std/%s: write use std/%s and %s.%s." name p p p name)
let hides_package name = plain (Printf.sprintf "%s is a package this file uses: choose another name here." name)
let pattern_struct name =
  hinted (Printf.sprintf "There is no struct \"%s\" here." name)
    "A pattern names a struct of this package, as Point(x, y), or of a package in use, as geo.Point(x, y)."
let method_foreign =
  plain "A method belongs to a struct or an interface declared in the same package: this one can't be reached from here."
let method_no_struct name =
  hinted (Printf.sprintf "There is no struct or interface \"%s\" in this package." name)
    "A method belongs to a struct or an interface declared in the same package."
let package_twice name other line = plain (Printf.sprintf "\"%s\" is also defined at %s:%d." name other line)
let method_nested = plain "A method can only be defined at the top of a file."
let method_both sname name =
  hinted (Printf.sprintf "%s has an instance method and a static method named \"%s\"." sname name) "A struct has one method of a name."
let method_field sname name = plain (Printf.sprintf "The method \"%s\" has the name of a field of %s." name sname)
let method_uncalled sname name =
  hinted (Printf.sprintf "\"%s\" is a method of %s: it must be called." name sname)
    (Printf.sprintf "Write x.%s(). On an array: list.Map(it.%s(), xs)." name name)
let static_on_value sname name =
  hinted (Printf.sprintf "\"%s\" is a static method of %s." name sname) (Printf.sprintf "Write %s.%s(...)." sname name)
let needs_object sname name =
  hinted (Printf.sprintf "\"%s\" needs a %s." name sname) (Printf.sprintf "Write x.%s(), with x a %s." name sname)
let no_static sname name = plain (Printf.sprintf "%s has no static method \"%s\"." sname name)
let no_member sname name = plain (Printf.sprintf "%s has no field or method \"%s\"." sname name)
let unset name = hinted (Printf.sprintf "\"%s\" has no value yet." name) "Give it a value before reading it."

let text_hint = "To put a value in a text, write \"...$x\" or value.Text(x)."

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
let date_outside x = plain (Printf.sprintf "date.Local can't place %g seconds since 1970: it takes a time less than 10^15 seconds from 1970, about 31 million years." x)
let random_range low high = plain (Printf.sprintf "random.Int needs a low that is at most its high, and a range that fits in 63 bits: %d to %d." low high)
let limit what = plain (Printf.sprintf "Limit \"%s\" reached." what)
let too_many fname want got = plain (Printf.sprintf "%s takes %d arguments, not %d." fname want got)
let missing_arg fname param = plain (Printf.sprintf "%s needs the argument \"%s\"." fname param)
let unknown_arg fname name = plain (Printf.sprintf "%s has no argument named \"%s\"." fname name)
let duplicate_arg fname name = plain (Printf.sprintf "%s received the argument \"%s\" twice." fname name)
let duplicate name = plain (Printf.sprintf "The function \"%s\" is defined twice." name)
let assign_function name = plain (Printf.sprintf "\"%s\" is a function of this file and can't be assigned." name)
let return_outside = plain "return can only be used inside a function."
let whole_hint = "To get a whole number, use math.Floor(...), math.Ceil(...) or math.Round(...)."
let range_bound a = hinted (Printf.sprintf "A range needs whole numbers, not %s." a) whole_hint
let index_type a = hinted (Printf.sprintf "An index must be a whole number, not %s." a) whole_hint
let index_outside i n = plain (Printf.sprintf "Index %d is outside this array of %d elements." i n)
let index_outside2 i j r c = plain (Printf.sprintf "Index [%d, %d] is outside this array of %d rows and %d columns." i j r c)
let sizes_text sizes = String.concat " by " (Array.to_list (Array.map string_of_int sizes))
let index_outside_nd ixs sizes =
  plain (Printf.sprintf "Index [%s] is outside this array of %s." (String.concat ", " (Array.to_list (Array.map string_of_int ixs))) (sizes_text sizes))
let index_slice_nd n = plain (Printf.sprintf "An array of %d dimensions takes a whole number for each index, not a slice." n)
let index_write = plain "Only one element can be written at a time."
let index_value a = plain (Printf.sprintf "Can't index %s." a)
let mask_size got want = plain (Printf.sprintf "This mask has %d elements, the array has %d." got want)
let cant_loop a = plain (Printf.sprintf "Can't loop over %s." a)
let cant_in a = plain (Printf.sprintf "Can't look inside %s with \"in\"." a)
let rows_differ = plain "The rows of this array have different lengths."
let semis_in_array =
  hinted "Two ; in a row: an array written in the code has rows and columns only."
    "An array of more dimensions comes from matrix.Reshape: [1 3; 2 4;;; 5 7; 6 8] is matrix.Reshape([2, 2, 2], 1..8)."
let bad_size name a = plain (Printf.sprintf "%s needs a size, not %s." name a)
let len_result sname a = plain (Printf.sprintf "The method len of %s must give an integer for value.Len, not %s." sname a)
let reshape_size n sizes = plain (Printf.sprintf "Can't reshape %d elements into %s." n (sizes_text sizes))
let reshape_shape a = hinted (Printf.sprintf "Reshape needs its shape as a list of sizes, not %s." a) "Write the sizes in a list: matrix.Reshape([2, 3], xs)."
let dim_outside name n a =
  plain (Printf.sprintf "%s's dimension must be %s, not %s." name (if n = 2 then "1 or 2" else Printf.sprintf "from 1 to %d" n) a)
let too_many_dims n = plain (Printf.sprintf "An array has at most 32 dimensions, not %d." n)
let two_dims name n = plain (Printf.sprintf "%s works on arrays of 2 dimensions, not %d." name n)
let shape a b = plain (Printf.sprintf "Can't combine an array of %s with an array of %s." (sizes_text a) (sizes_text b))
let matmul_shape a b c d =
  plain (Printf.sprintf "Matmul can't multiply %d by %d with %d by %d: the columns of the first must equal the rows of the second." a b c d)
let decimals_count a = plain (Printf.sprintf "text.Decimals needs a count of decimals from 0 to 20, not %s." a)
let need_number name a =
  let text = Printf.sprintf "%s needs numbers, not %s." name a in
  if a = "function <anonymous>" then hinted text "\"it\" belongs to the nearest call. Write x -> ... to use it further out."
  else plain text
let it_assign = plain "\"it\" is a reserved name and can't be assigned."
let no_field name = plain (Printf.sprintf "This struct has no field \"%s\"." name)
let named_field sname name = plain (Printf.sprintf "%s has no field \"%s\"." sname name)
let from_static sname =
  hinted (Printf.sprintf "%s.From is a static method of every struct: it can't be defined." sname)
    "Another name, as FromRow, can build a struct its own way."
let from_private sname = plain (Printf.sprintf "%s needs a field that is private to its package." sname)
let fields_of a = plain (Printf.sprintf "Fields needs a struct, not %s." a)
let from_missing sname name = plain (Printf.sprintf "%s needs the field \"%s\"." sname name)
let from_twice sname a b field = plain (Printf.sprintf "%s gets its field \"%s\" from two keys: \"%s\" and \"%s\"." sname field a b)
let field_of a name = plain (Printf.sprintf "Can't read the field \"%s\" of %s." name a)
let struct_nested = plain "A struct can only be defined at the top of a file."
let struct_not_field =
  hinted "Only fields can be written inside a struct."
    "One per line: a name, its type if it has one, and = with a default. The struct ends with end."
let struct_line = plain "In the block form of a struct, each field has its own line."
let lambda_type = hinted "The parameters of a lambda can't have types." "Write the function with defn to give them some."
let no_type name =
  hinted (Printf.sprintf "There is no type \"%s\"." name)
    "A type is Int, Float, Number, Bool, Text, Array, Dict, Function, a struct or an interface."
let interface_nested = plain "An interface can only be defined at the top of a file."
let interface_not_method =
  hinted "Only methods can be written inside an interface."
    "A method is a name and its parameters in parentheses, as Area() or Scaled(by Number)."
let interface_body =
  hinted "A method of an interface has no body."
    "A method written apart, as (s Shape) Describe() = ..., is a method of every value that meets the interface."
let interface_line = plain "In the block form of an interface, each method has its own line."
let interface_default = plain "A parameter of an interface has no default."
let interface_call name =
  hinted (Printf.sprintf "%s is an interface: it can't be called." name)
    (Printf.sprintf "A value meets it by having its methods. To check one, write the interface after a parameter or a field: s %s."
       name)
let method_two a b name found =
  hinted (Printf.sprintf "Both %s and %s have a method \"%s\", and %s meets both." a b name found)
    "A field or a method of the value itself would win over theirs."
let wrong_type fname name want found = plain (Printf.sprintf "%s: %s must be %s, found %s." fname name want found)
let wrong_result fname = wrong_type fname "the result"
let result_plain name = hinted (Printf.sprintf "%s gives a result, used here as a plain value." name) "An Err would pass for a value: add ?, match it, or Unwrap it."
let result_dropped name = hinted (Printf.sprintf "%s gives a result, which is dropped here." name) "Its Err would go unseen: add ?, match it, or write _ = before it to drop it on purpose."
let missing_bang fname t = plain (Printf.sprintf "%s can give an Err, which %s doesn't say: write %s!." fname t t)
let use_broken upath at = plain (Printf.sprintf "Package %s doesn't load: %s." upath at)
let bang_value = hinted "Only the result of a function can end with !." "Int! says that a function gives an Ok of an Int, or an Err: defn Size(path) Int!."
let article name = (if name <> "" && String.contains "AEIOUaeiou" name.[0] then "an " else "a ") ^ name
let destructure_array want got = plain (Printf.sprintf "This pattern takes %d elements, the value has %d." want got)
let destructure_struct a = plain (Printf.sprintf "This pattern needs a struct, not %s." a)
let destructure_value a = plain (Printf.sprintf "This pattern needs an array, not %s." a)
let pattern_mismatch name a = plain (Printf.sprintf "This pattern needs %s, not %s." name a)
let question_file = hinted "? can only be used inside a function, which it leaves with the Err." "At the top of a file, write result.Unwrap(...) where an Err would be a bug, or match on the result."
let question_space = plain "? must follow its value, with no space."
let question_value a =
  hinted (Printf.sprintf "? needs an Ok or an Err, not %s." a) "Return a result from the function you call."
let need_task name a = plain (Printf.sprintf "%s needs a task, not %s." name a)
let empty_text name = plain (Printf.sprintf "%s needs a text that isn't empty." name)
let need_array name a = plain (Printf.sprintf "%s needs an array, not %s." name a)
let c_no_library name reason = plain (Printf.sprintf "Can't load %s: %s." name reason)
let c_no_function name = plain (Printf.sprintf "This library has no function %s." name)
let c_type name = plain (Printf.sprintf "%s isn't a C type." name)
let c_void_arg = plain "void can't be an argument."
let c_too_many n = plain (Printf.sprintf "A C function takes at most 60 arguments, not %d." n)
let c_no_ffi = plain "This needs libffi, which isn't installed."
let c_bad_signature = plain "libffi refuses this signature."
let c_need_struct a = plain (Printf.sprintf "A structure needs a block, not %s." a)
let c_small_block got want = plain (Printf.sprintf "This block has %d bytes, and the structure takes %d." got want)
let c_need_callback a = plain (Printf.sprintf "callback needs a callback, not %s." a)
let c_need_function a = plain (Printf.sprintf "c.Callback needs a function, not %s." a)
let c_struct_empty = plain "c.Struct needs at least one field."
let c_struct_field name = plain (Printf.sprintf "%s can't be a field of a structure." name)
let c_field_index k n = plain (Printf.sprintf "Field %d is outside this structure of %d fields." k n)
let c_need_layout name a = plain (Printf.sprintf "%s needs a structure type, not %s." name a)
let c_variadic_type name = plain (Printf.sprintf "%s can't be a variadic argument: C promotes it. Use i32 or f64." name)
let c_callback_type name = plain (Printf.sprintf "%s can't go through a callback." name)
let c_need_library a = plain (Printf.sprintf "c.Fn needs a library, not %s." a)
let c_version a = plain (Printf.sprintf "c.Open needs a version as an integer or a text, not %s." a)
let c_fit v ty = plain (Printf.sprintf "%s doesn't fit in %s." v ty)
let c_return_fit ty = plain (Printf.sprintf "This %s doesn't fit in an integer." ty)
let c_need_integer ty a = plain (Printf.sprintf "%s needs an integer, not %s." ty a)
let c_need_number ty a = plain (Printf.sprintf "%s needs a number, not %s." ty a)
let c_need_bool a = plain (Printf.sprintf "bool needs true or false, not %s." a)
let c_need_ptr a = plain (Printf.sprintf "ptr needs a pointer, a block or missing, not %s." a)
let c_need_text a = plain (Printf.sprintf "text needs a text or missing, not %s." a)
let c_size a = plain (Printf.sprintf "c.Alloc needs a size of 1 or more, not %s." a)
let c_offset o size ty =
  let article = if ty.[0] = 'i' || ty.[0] = 'f' then "an" else "a" in
  plain (Printf.sprintf "Offset %d is outside this block of %d bytes for %s %s." o size article ty)
let c_need_offset a = plain (Printf.sprintf "An offset is an integer, not %s." a)
let c_need_numbers a = plain (Printf.sprintf "c.Write needs an array of numbers, not %s." a)
let c_write_past o n ty size =
  plain (Printf.sprintf "c.Write of %d %s of %s from offset %d goes past this block of %d bytes." n (if n = 1 then "value" else "values") ty o size)
let c_block_type verb ty = plain (Printf.sprintf "%s can't be %s a block." ty verb)
let c_need_block name a = plain (Printf.sprintf "c.%s needs a block, not %s." name a)
let c_need_pointer a = plain (Printf.sprintf "c.Text needs a pointer, not %s." a)
let c_freed = plain "This block was freed."
let c_no_open_library = hinted "Nothing of C runs before a library is open: structures, pointers and calls wait for c.Open." "Call c.Open first: it checks the ffi permission for the whole of std/c."
let c_zero_byte = plain "This text has a zero byte, which C would read as its end."
let bad_duration name a = plain (Printf.sprintf "%s needs a finite duration of 0 or more, not %s." name a)
let io_failure verb target why = plain (Printf.sprintf "Can't %s %s: %s." verb target why)
let need_socket name a = plain (Printf.sprintf "%s needs a socket, not %s." name a)
let need_port a = plain (Printf.sprintf "A port is a number from 0 to 65535, not %s." a)
let socket_closed = plain "This socket is closed."
let no_random = plain "The system gave no random bytes: a WebSocket client needs them for its keys."
let too_many_sockets = plain "This system can't watch more sockets."
let server_stopped = plain "The server is stopping."
let log_fields a = plain (Printf.sprintf "The fields of a log line are a struct or a dictionary, not %s." a)
let metric_labels a = plain (Printf.sprintf "The labels of a metric are a struct or a dictionary, not %s." a)
let metric_name s =
  plain (Printf.sprintf "%S isn't a name Prometheus takes: letters, digits and _, not first a digit." s)
let metric_kind name kind = plain (Printf.sprintf "The metric %s is a %s: it can't be another kind too." name kind)
let metric_negative n = plain (Printf.sprintf "A counter only grows: metrics.Add takes 0 or more, not %g." n)
let workers_ended pid code = plain (Printf.sprintf "Worker %d ended with code %d: another starts." pid code)
let workers_cant_start code =
  plain (Printf.sprintf "A worker ended with code %d before it could accept: the program can't start, the workers stop." code)
let workers_new_ended code =
  plain (Printf.sprintf "A new worker ended with code %d before it could accept: the running workers stay." code)
let workers_new_late = plain "The new workers didn't accept in time: the running workers stay."
let invalid_workers s = "invalid number of workers: " ^ s ^ ", a whole number from 1, or cores"
let workers_watch = "--workers and --watch don't go together: --watch reloads one process"
let workers_windows = "--workers needs Linux or macOS: on Windows, a program serves on one core"
let bad_char a = plain (Printf.sprintf "Char needs a code point, not %s." a)
let need_size name a = plain (Printf.sprintf "%s needs a number of bytes within the text, not %s." name a)
let deadlock = plain "All fibers are waiting and nothing can wake them."
let index_count n = plain (Printf.sprintf "This array has %d dimensions: use %d indexes, or one." n n)
let range_too_long = plain "This range has too many elements."
let no_on_stop = plain "The debugger has no function OnStop(stop)."
let no_main = plain "This tool has no function Main()."
let debug_plugin reason = plain ("The debugger's engine didn't load: " ^ reason ^ ".")
let need_frame a = plain (Printf.sprintf "Eval needs a frame of a stop, as stop.Frames[1], not %s." a)
let bad_answer a =
  plain (Printf.sprintf "OnStop must return \"continue\", \"step\", \"next\" or \"out\", not %s." a)
let need_text name a = plain (Printf.sprintf "%s needs a text, not %s." name a)
let need_flag name a = plain (Printf.sprintf "%s needs true or false, not %s." name a)
let empty_array name = plain (name ^ " of an empty array.")
let usage =
  "usage: cesia run [--allow LIST] [--limit LIST] [--watch] [--workers N] [--debugger FILE] [--repl] [--cells] [--no-spec] [--no-jit] [--seed N] file.ce [args...]\n\
  \       cesia test [path | file.ce:isName] [--seed N] [--cases N] [--update] [--allow LIST] [--no-spec]\n\
  \       cesia check [--json] [--stdin file.ce] [path...]\n\
  \       cesia fmt [--check] [path...]\n\
  \       cesia lsp\n\
  \       cesia do [task]\n\
  \       cesia new name\n\
  \       cesia pkg [install | update [label] [--to tag] | add url@tag [package...] | move old new | --check]\n\
  \       cesia upgrade [--nightly]\n\
  \       cesia doc [name]\n\
  \       cesia doc --site [folder] [--open]\n\
  \       cesia version"
let cant_read path = "can't read " ^ path
let unknown_permission name = "unknown permission: " ^ name
let invalid_permission item = "invalid permission: " ^ item
let invalid_size s = "invalid size: " ^ s
let invalid_limit s = "invalid limit: " ^ s
let invalid_seed s = "invalid seed: " ^ s ^ ", a whole number"
let unknown_limit name = "unknown limit: " ^ name
let internal e = "Internal error: " ^ e
let toml_utf8 = "This line is not valid UTF-8."
let toml_control = "Control characters aren't allowed here."
let toml_unsupported what = what ^ " aren't supported in this file."
let toml_strings_only = "Arrays hold strings only in this file."
let toml_expected what = Printf.sprintf "Expected %s." what
let toml_string_open = "This string is not closed."
let toml_array_open = "This array is not closed."
let toml_escape c = Printf.sprintf "The escape \\%c isn't supported in this file." c
let toml_twice name = name ^ " is defined twice."
let at_line line text = Printf.sprintf "cesia.toml:%d: %s" line text
let project_no_file = "No cesia.toml in this folder."
let project_no_name = "cesia.toml has no name in [project]."
let project_no_task = "cesia.toml has no task."
let project_table path = Printf.sprintf "Unknown table [%s]." path
let project_outside key = Printf.sprintf "Unknown field %s outside any table." key
let project_field subject key = Printf.sprintf "%s has an unknown field %s." subject key
let project_type subject key what = Printf.sprintf "%s: %s needs %s." subject key what
let project_empty_run name = Printf.sprintf "Task %s: run needs at least one word." name
let project_both name = Printf.sprintf "Task %s has both run and file." name
let project_without_file name key = Printf.sprintf "Task %s has %s without file." name key
let project_missing name need = Printf.sprintf "Task %s needs %s, which doesn't exist." name need

let project_cycle name through =
  match through with
  | [] -> Printf.sprintf "Task %s needs itself." name
  | _ -> Printf.sprintf "Task %s needs itself, through %s." name (String.concat ", " through)

let project_listed_needs needs = Printf.sprintf "(needs %s)" (String.concat ", " needs)
let project_bad_name name = Printf.sprintf "A project name holds letters, digits, - and _, not %s." name
let project_exists name = name ^ " already exists."
let project_created name = Printf.sprintf "Created %s. Run it: cd %s && cesia do run" name name
let project_no_such_task name = Printf.sprintf "No task named %s." name
let project_cant_start program reason = Printf.sprintf "Can't start %s: %s." program reason
let need_count name a = plain (Printf.sprintf "%s needs a count of 0 or more, not %s." name a)
let cant_sort a b = plain (Printf.sprintf "Can't sort %s with %s." a b)
let need_char name = plain (Printf.sprintf "%s needs a text with a character." name)
let need_byte a = plain (Printf.sprintf "FromBytes needs integers from 0 to 255, not %s." a)
let doc_missing name = "cesia: nothing is documented under " ^ name
let doc_moved name p = Printf.sprintf "cesia: %s is in std/%s: cesia doc %s.%s." name p p name
let json_value a = plain (Printf.sprintf "JSON can't hold %s." a)
let column_sizes a b = plain (Printf.sprintf "These columns have %d and %d rows." a b)
let need_groups a = plain (Printf.sprintf "Split needs the result of Groups, not %s." a)
let json_at text byte = Printf.sprintf "%s, at byte %d." text byte
let json_unexpected = "Unexpected text"
let json_short_escape = "A \\u escape is too short"
let json_hex_escape = "A \\u escape needs four hex digits"
let json_surrogate = "A surrogate is alone"
let json_open_text = "A text is not closed"
let json_bad_escape = "A bad escape"
let json_control = "A control character in a text"
let json_digits = "A number needs digits"
let json_large = "A number is too large"
let json_deep = "Too deep"
let json_no_value = "Expected a value"
let json_no_comma_array = "Expected a comma or ]"
let json_key = "A key needs a text"
let json_colon = "Expected a colon"
let json_no_comma_object = "Expected a comma or }"
let json_after = "Text after the value"
let regex_bad why = plain (Printf.sprintf "Bad pattern: %s." why)
let process_ended = plain "This process has ended."
let need_process name a = plain (Printf.sprintf "%s needs a process, not %s." name a)
let input_closed = plain "The input of this process is closed."
let dict_key a = plain (Printf.sprintf "A dictionary key is a number or a text, not %s." a)
let dict_absent k = plain (Printf.sprintf "This dictionary has no key: %s." k)
let dict_index = plain "A dictionary takes one key between its brackets."
let dict_pair a = plain (Printf.sprintf "Dict needs structs with a Key and a Value, not %s." a)
let need_dict name a = plain (Printf.sprintf "%s needs a dictionary, not %s." name a)
let map_of_struct name sn =
  hinted (Printf.sprintf "%s needs a dictionary, not %s." name (article sn)) "dict.Fields(x) gives the public fields of a struct as a dictionary."
let no_match a = plain (Printf.sprintf "No branch of this match accepts %s." a)
let assertion = plain "Assertion failed."
let use_nested = plain "use can only be used at the top of a file."
let use_cycle = plain "This use creates a cycle between modules."
let use_quoted path =
  let rec from_root p =
    let drop n = from_root (String.sub p n (String.length p - n)) in
    if String.starts_with ~prefix:"./" p then drop 2 else if String.starts_with ~prefix:"../" p then drop 3 else p
  in
  hinted "A use takes no quotes: it names a package of the project." (Printf.sprintf "Write use %s." (from_root path))
let use_relative = hinted "A use starts in src/ or at the root of the project, with no ./ and no ../." "Write the whole path: use geometry/shapes."
let use_empty path = plain (Printf.sprintf "The folder \"%s\" holds no .ce file." path)
let use_same name other line =
  hinted (Printf.sprintf "\"%s\" already names %s, at line %d." name other line) "Give one of them another name with as."
let use_unreadable path = plain (Printf.sprintf "Can't read the module \"%s\"." path)
let reload_use = plain "A running program can't load a new module. Restart it to use this one."
let use_missing path = plain (Printf.sprintf "Module \"%s\" doesn't exist." path)
let use_std name = plain (Printf.sprintf "What comes with Cesia is used through std/: write use std/%s." name)
let use_path name folder = plain (Printf.sprintf "A use is the path of a folder from the root of the project: write use %s." (if folder = "" then name else folder))
let source_missing dir = plain (Printf.sprintf "The source folder \"%s\" doesn't exist." dir)
let source_outside dir = plain (Printf.sprintf "The source folder \"%s\" is outside the project." dir)

let cesia_needed needed this =
  plain (Printf.sprintf "This project needs Cesia %s or later, and this is %s: run cesia upgrade." needed this)

let cesia_not_version = "a version such as \"0.2\""
let changed_by_hand path = plain (Printf.sprintf "%s was changed by hand: run cesia pkg install." path)
let not_installed folder = plain (Printf.sprintf "%s isn't installed: run cesia pkg install." folder)
let use_dep upath =
  plain (Printf.sprintf "%s names no package: a use of deps/ is deps/OWNER/REPO then the path of a folder from its root, as the [deps] of cesia.toml bring it." upath)
let no_name alias name = plain (Printf.sprintf "Module \"%s\" has no name \"%s\"." alias name)
(* The narrowest permission that would do: the file, the port, the host, the command, the variable or the library asked for. *)
let exit_code a = plain (Printf.sprintf "sys.Exit takes a code from 0 to 255, not %s." a)

let denied perm target =
  match target with
  | None | Some "" -> plain (Printf.sprintf "Permission \"%s\" denied. Run again with --allow %s." perm perm)
  | Some t ->
    let what = if perm = "net" && t.[0] = ':' then "port " ^ String.sub t 1 (String.length t - 1) else t in
    let folder = if perm = "read" || perm = "write" then ", or a folder that holds it" else "" in
    hinted (Printf.sprintf "Permission \"%s\" denied for %s." perm what)
      (Printf.sprintf "Run again with --allow %s=%s%s." perm t folder)
let need_struct name a = plain (Printf.sprintf "%s needs a struct, not %s." name a)
let test_only = plain "std/test and std/gen work under cesia test, in a test function of a .test.ce file or a tests folder."
let test_case i n = Printf.sprintf "at case %d of %d" i n
let test_saved_case = "on the case an earlier run saved"
let test_shrunk a b = Printf.sprintf ", shrunk from %d draws to %d:" a b
let test_panic m = "it stopped: " ^ m
let test_unknown path name tests =
  Printf.sprintf "%s: no test is named %s; %s." path name
    (match tests with [] -> "the file has none" | _ -> "its tests are " ^ String.concat ", " tests)
let test_exit code = Printf.sprintf "it called sys.Exit(%d), which would end the whole run." code
let test_replay path seed = Printf.sprintf "saved, tried first next time; these cases again: cesia test %s --seed %d" path seed
let test_summary passed failed seed =
  Printf.sprintf "%d passed, %d failed%s" passed failed (match seed with Some s -> Printf.sprintf ", seed %d" s | None -> "")
let snapshot_new k = Printf.sprintf "new snapshot %d: review it, then cesia test --update" k
let snapshot_changed k = Printf.sprintf "snapshot %d changed: cesia test --update keeps the new text" k
let no_test_plugin reason = "cesia test needs its plugin, cesia_testing.cmxs, beside the binary: " ^ reason
let test_part i n = Printf.sprintf ", part %d of %d" i n
let test_question line = Printf.sprintf " at the ? of line %d" line
let test_last_bits a b = Printf.sprintf "the same float but for its last bits: math.Near(%s, %s)?" a b
let test_rel_zero = "rel can't help at 0: give abs"
let test_bools = "== compares element by element: value.Equal(a, b)?"
let not_own target =
  hinted
    (Printf.sprintf "Permission \"net\" denied for %s: net=own reaches only the listeners this program has open, at an address of this machine written out or localhost." target)
    (Printf.sprintf "Run again with --allow net=%s; for cesia test, \"net=%s\" in allow of [test] in cesia.toml does it too." target target)
let test_timeout seconds =
  hinted (Printf.sprintf "The test ran past its %g s." seconds) "timeout of [test] in cesia.toml gives a test more time."
let test_temp path = "Its Temp folder is kept: " ^ path
let near_tolerance name v = plain (Printf.sprintf "Near needs %s to be a number of 0 or more, not %s." name v)
let listen_denied target port =
  hinted (Printf.sprintf "Permission \"net\" denied for listening on %s, which other machines can reach." target)
    (Printf.sprintf "Run again with --allow net=%s; net=:%d listens on this machine only." target port)
let rows_same_key a b key =
  plain (Printf.sprintf "The columns %s and %s both give the key %s: rename one with as." a b key)
let rows_cells cells names = plain (Printf.sprintf "%d cells don't make whole rows of %d names." cells names)
let sql_zero_byte what = plain (Printf.sprintf "SQLite can't take %s with a zero byte." what)
let sql_need_handle name kind a = plain (Printf.sprintf "%s needs a %s, not %s." name kind a)
let sql_closed = plain "This connection or cursor is closed."
let sql_store_directory =
  plain "SQLite's pragmas temp_store_directory and data_store_directory are refused: they would put its files where read= and write= don't reach."
let native_table = plain "[native] needs package, the folder of a package of the project, and natives, an array of the names of its natives."
let native_public name =
  plain (Printf.sprintf "[native] natives: %s isn't a private name, as a native of a package is: a small first letter, no _." name)
let engine_missing folder wanted found =
  let has = if found = [] then "" else Printf.sprintf " (it has %s)" (String.concat ", " found) in
  if folder = "" then plain (Printf.sprintf "native/ has no engine for %s%s: build the engine of this project." wanted has)
  else plain (Printf.sprintf "%s has no engine for %s%s: run cesia pkg install." folder wanted has)
let engine_lacks name = plain (Printf.sprintf "it needs %s, which this Cesia doesn't hold" name)
let engine_changed path = plain (Printf.sprintf "%s changed since this Cesia loaded it: run the program again." path)
let engine_refused path reason = plain (Printf.sprintf "The engine %s didn't load: %s." path reason)
let engine_names path missing extra =
  let part what = function [] -> [] | names -> [ what ^ " " ^ String.concat ", " names ] in
  plain (Printf.sprintf "The engine %s doesn't give the natives of its cesia.toml: %s." path
           (String.concat "; " (part "it lacks" missing @ part "it adds" extra)))
let engine_misuse what = plain (Printf.sprintf "Cesia_v1.%s, by a native package." what)
let native_raised name e = plain (Printf.sprintf "%s raised %s: a bug of its native package." name e)
let native_needs name want got = plain (Printf.sprintf "%s needs %s, not %s." name want got)
let sql_plugin reason = plain (Printf.sprintf "Can't load SQLite's plugin cesia_sqlite.cmxs: %s." reason)
let sql_no_statement = plain "The text holds no statement."
let sql_statements = plain "One statement per call: sql.Script runs several, without parameters."
let sql_bad_param k a =
  plain (Printf.sprintf "Parameter %d is %s: SQL takes missing, a Bool, an Int, a Float or a Text." k a)
let sql_param_count wanted given =
  plain (Printf.sprintf "The statement has %d placeholders, given %d values: one value for each ?." wanted given)
let sql_batch a = plain (Printf.sprintf "A batch needs a count of rows above 0, not %s." a)
let sql_int_past name =
  plain (Printf.sprintf "The column %s holds an integer past 63 bits: read it with cast(%s as text)." name name)
let need_channel name a = plain (Printf.sprintf "%s needs a channel, not %s." name a)
let bad_timeout a = plain (Printf.sprintf "A timeout is a number of seconds, 0 or more, not %s." a)
let receive_timeout = plain "Nothing came on the channel before the timeout."
let wait_timeout = plain "The task didn't end before the timeout."
let cancelled = plain "The fiber was cancelled here."
let send_closed = plain "Send to a closed channel: Close said that nothing more comes."
let closed_twice = plain "This channel is closed already."
let channel_closed = plain "The channel is closed, and nothing is left in it."
let select_timeout = plain "Nothing came on the channels before the timeout."
let need_channels a = plain (Printf.sprintf "Select needs a list of channels, not %s." a)
let channel_size a = plain (Printf.sprintf "The size of a channel is a whole number, 0 or more, not %s." a)
let sql_db_closed = plain "This database is closed."
let sql_pool wait = plain (Printf.sprintf "No connection was free for %g seconds. Inside a transaction, use its tx, not db." wait)
let sql_pool_size a = plain (Printf.sprintf "A pool holds 1 connection or more, not %s." a)
let sql_uri path = plain (Printf.sprintf "%s is a URI: SQLite takes the path of a file here, or :memory:." path)
let c_sqlite name = plain (Printf.sprintf "%s is SQLite, which programs reach through std/sql only." name)
