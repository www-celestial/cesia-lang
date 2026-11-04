type t = { text : string; hint : string option }

let plain text = { text; hint = None }
let hinted text hint = { text; hint = Some hint }

let fits = "Integers have 63 bits. To go further, use a float: 1.0 * x."
let invalid_utf8 = plain "This file is not valid UTF-8."
let unexpected_char c = plain (Printf.sprintf "Unexpected character %C." c)
let text_not_closed = plain "This text is not closed: a closing \" is missing."
let comment_not_closed = plain "This comment is not closed: a closing *) is missing."
let comment_dashes = plain "Comments are written (* ... *)."
let number_too_big s = hinted (Printf.sprintf "The number %s doesn't fit in 63 bits." s) (Printf.sprintf "Write it as a float: %s.0." s)
let expected what got = plain (Printf.sprintf "Expected %s, found %s." what got)
let too_nested = plain "This code is nested too deeply."
let cant_assign = plain "Only a variable can be assigned here."
let break_outside = plain "break can only be used inside a loop."
let underscore_name name small capital =
  let text = Printf.sprintf "A name can't hold a _: \"%s\"." name in
  if small = "" then plain text
  else hinted text (Printf.sprintf "Join the words with capitals: %s, or %s when it is public." small capital)
let private_field name =
  hinted (Printf.sprintf "The field \"%s\" is private to the package that declares it." name)
    "A field is public when its first letter is a capital."
let private_member name =
  hinted (Printf.sprintf "The field or method \"%s\" is private to the package that declares it." name)
    "A field or a method is public when its first letter is a capital."
let undefined name = plain (Printf.sprintf "Name \"%s\" doesn't exist." name)
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
    (Printf.sprintf "Write x.%s(). On an array: Map(it.%s(), xs)." name name)
let static_on_value sname name =
  hinted (Printf.sprintf "\"%s\" is a static method of %s." name sname) (Printf.sprintf "Write %s.%s(...)." sname name)
let needs_object sname name =
  hinted (Printf.sprintf "\"%s\" needs a %s." name sname) (Printf.sprintf "Write x.%s(), with x a %s." name sname)
let no_static sname name = plain (Printf.sprintf "%s has no static method \"%s\"." sname name)
let no_member sname name = plain (Printf.sprintf "%s has no field or method \"%s\"." sname name)
let unset name = hinted (Printf.sprintf "\"%s\" has no value yet." name) "Give it a value before reading it."

let text_hint = "To put a value in a text, write \"...$x\" or Text(x)."

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
let whole_hint = "To get a whole number, use Floor(...), Ceil(...) or Round(...)."
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
let size_dim a = plain (Printf.sprintf "Size's dimension must be 1 or 2, not %s." a)
let shape a b c d = plain (Printf.sprintf "Can't combine an array of %d by %d with an array of %d by %d." a b c d)
let matmul_shape a b c d =
  plain (Printf.sprintf "Matmul can't multiply %d by %d with %d by %d: the columns of the first must equal the rows of the second." a b c d)
let need_number name a =
  let text = Printf.sprintf "%s needs numbers, not %s." name a in
  if a = "function <anonymous>" then hinted text "\"it\" belongs to the nearest call. Write x -> ... to use it further out."
  else plain text
let it_assign = plain "\"it\" is a reserved name and can't be assigned."
let no_field name = plain (Printf.sprintf "This struct has no field \"%s\"." name)
let named_field sname name = plain (Printf.sprintf "%s has no field \"%s\"." sname name)
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
let article name = (if name <> "" && String.contains "AEIOUaeiou" name.[0] then "an " else "a ") ^ name
let destructure_array want got = plain (Printf.sprintf "This pattern takes %d elements, the value has %d." want got)
let destructure_struct a = plain (Printf.sprintf "This pattern needs a struct, not %s." a)
let destructure_value a = plain (Printf.sprintf "This pattern needs an array, not %s." a)
let pattern_mismatch name a = plain (Printf.sprintf "This pattern needs %s, not %s." name a)
let question_file = plain "? can only be used inside a function."
let question_space = plain "? must follow its value, with no space."
let question_value a =
  hinted (Printf.sprintf "? needs an Ok or an Err, not %s." a) "Return a result from the function you call."
let need_task a = plain (Printf.sprintf "Wait needs a task, not %s." a)
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
let c_block_type verb ty = plain (Printf.sprintf "%s can't be %s a block." ty verb)
let c_need_block name a = plain (Printf.sprintf "c.%s needs a block, not %s." name a)
let c_need_pointer a = plain (Printf.sprintf "c.Text needs a pointer, not %s." a)
let c_freed = plain "This block was freed."
let c_no_open_library = plain "Reading a pointer needs an open library."
let c_zero_byte = plain "This text has a zero byte, which C would read as its end."
let bad_sleep a = plain (Printf.sprintf "Sleep needs a finite duration of 0 or more, not %s." a)
let io_failure verb target why = plain (Printf.sprintf "Can't %s %s: %s." verb target why)
let need_socket name a = plain (Printf.sprintf "%s needs a socket, not %s." name a)
let need_port a = plain (Printf.sprintf "A port is a number from 0 to 65535, not %s." a)
let socket_closed = plain "This socket is closed."
let too_many_sockets = plain "This system can't watch more sockets."
let server_stopped = plain "The server is stopping."
let bad_char a = plain (Printf.sprintf "Char needs a code point, not %s." a)
let need_size name a = plain (Printf.sprintf "%s needs a number of bytes within the text, not %s." name a)
let deadlock = plain "All fibers are waiting and nothing can wake them."
let index_count = plain "An array has 2 dimensions: use one or two indexes."
let range_too_long = plain "This range has too many elements."
let no_on_stop = plain "The debugger has no function OnStop(stop)."
let bad_answer a =
  plain (Printf.sprintf "OnStop must return \"continue\", \"step\", \"next\" or \"out\", not %s." a)
let need_text name a = plain (Printf.sprintf "%s needs a text, not %s." name a)
let empty_array name = plain (name ^ " of an empty array.")
let usage =
  "usage: cesia run [--allow LIST] [--limit LIST] [--watch] [--debugger FILE] [--no-spec] file.ce [args...]\n\
  \       cesia test [path] [--no-spec]\n\
  \       cesia do [task]\n\
  \       cesia new name\n\
  \       cesia pkg [update name...]\n\
  \       cesia doc [name]\n\
  \       cesia version"
let cant_read path = "can't read " ^ path
let unknown_permission name = "unknown permission: " ^ name
let invalid_permission item = "invalid permission: " ^ item
let invalid_size s = "invalid size: " ^ s
let invalid_limit s = "invalid limit: " ^ s
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
let pkg_not_library name = Printf.sprintf "\"%s\" is not a library of Cesia." name
let pkg_updated name = Printf.sprintf "pkg/%s is this Cesia's version again." name
let project_created name = Printf.sprintf "Created %s. Run it: cd %s && cesia do run" name name
let project_no_such_task name = Printf.sprintf "No task named %s." name
let project_cant_start program reason = Printf.sprintf "Can't start %s: %s." program reason
let need_count name a = plain (Printf.sprintf "%s needs a count of 0 or more, not %s." name a)
let cant_sort a b = plain (Printf.sprintf "Can't sort %s with %s." a b)
let need_char name = plain (Printf.sprintf "%s needs a text with a character." name)
let need_byte a = plain (Printf.sprintf "FromBytes needs integers from 0 to 255, not %s." a)
let doc_missing name = "cesia: nothing is documented under " ^ name
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
let use_both name folder = plain (Printf.sprintf "\"%s\" is both a module of the standard library and the folder %s." name folder)
let use_unreadable path = plain (Printf.sprintf "Can't read the module \"%s\"." path)
let no_prelude = plain "The folder of CESIA_STD has no prelude.ce."
let reload_use = plain "A running program can't load a new module. Restart it to use this one."
let use_missing path = plain (Printf.sprintf "Module \"%s\" doesn't exist." path)
let use_library name = plain (Printf.sprintf "\"%s\" is a library: write use pkg/%s." name name)
let use_binary name = plain (Printf.sprintf "\"%s\" is a module of the binary: write use %s." name name)
let source_missing dir = plain (Printf.sprintf "The source folder \"%s\" doesn't exist." dir)
let source_outside dir = plain (Printf.sprintf "The source folder \"%s\" is outside the project." dir)

let cesia_needed needed this =
  plain (Printf.sprintf "This project needs Cesia %s or later, and this is %s: run cesia upgrade." needed this)

let cesia_not_version = "a version such as \"0.2\""
let no_name alias name = plain (Printf.sprintf "Module \"%s\" has no name \"%s\"." alias name)
let denied perm = plain (Printf.sprintf "Permission \"%s\" denied. Run again with --allow %s." perm perm)
