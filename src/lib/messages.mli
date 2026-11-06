(** All error messages, in English. *)

type t = { text : string; hint : string option }

val plain : string -> t
val invalid_utf8 : t
val unexpected_char : char -> t
val text_not_closed : t
val text_doubled_quote : t
val comment_not_closed : t
val comment_dashes : t
val number_too_big : string -> t
val expected : string -> string -> t
val too_nested : t
val colon_range : t
val cant_assign : t
val break_outside : t
val underscore_name : string -> string -> string -> t
val private_member : string -> t
val undefined : string -> t

(** [moved name p]: a name of std/p written without its package, as Print for io.Print. *)
val moved : string -> string -> t

(** [hides_package name]: a variable, a parameter, a function or a pattern of a file is named as a package it uses. *)
val hides_package : string -> t

(** A pattern that names no struct the file sees. *)
val pattern_struct : string -> t
val method_foreign : t
val method_no_struct : string -> t

(** [package_twice name other line]: the other place that defines this name. *)
val package_twice : string -> string -> int -> t

val method_nested : t
val method_both : string -> string -> t
val method_field : string -> string -> t
val method_uncalled : string -> string -> t
val static_on_value : string -> string -> t
val needs_object : string -> string -> t
val no_static : string -> string -> t
val no_member : string -> string -> t
val unset : string -> t

(** [binary "add" a "and" b is_text]: [is_text] adds the hint about texts. *)
val binary : string -> string -> string -> string -> bool -> t

val overflow : string -> string -> string -> t
val overflow_neg : string -> t
val div_zero : string -> t
val negate : string -> t
val compare_op : string -> string -> string -> t
val condition : string -> t
val not_function : string -> t
val arg_count : string -> string -> int -> t
val want_int : string -> string -> t

(** [random_range low high]: random.Int(low, high) with low above high, or a range wider than an Int. *)
val random_range : int -> int -> t
val limit : string -> t
val too_many : string -> int -> int -> t
val missing_arg : string -> string -> t
val unknown_arg : string -> string -> t
val duplicate_arg : string -> string -> t
val duplicate : string -> t
val assign_function : string -> t
val return_outside : t
val range_bound : string -> t
val index_type : string -> t
val index_outside : int -> int -> t
val index_outside2 : int -> int -> int -> int -> t
val index_write : t
val index_value : string -> t
val mask_size : int -> int -> t
val cant_loop : string -> t
val cant_in : string -> t
val rows_differ : t
val bad_size : string -> string -> t
val reshape_size : int -> int -> int -> t
val size_dim : string -> t
val shape : int -> int -> int -> int -> t
val matmul_shape : int -> int -> int -> int -> t
val need_number : string -> string -> t
val no_field : string -> t
val named_field : string -> string -> t
val from_missing : string -> string -> t
val from_twice : string -> string -> string -> string -> t
val from_static : string -> t
val fields_of : string -> t
val from_private : string -> t
val field_of : string -> string -> t
val struct_nested : t
val struct_not_field : t
val struct_line : t
val lambda_type : t
val no_type : string -> t
val interface_nested : t
val interface_not_method : t
val interface_body : t
val interface_line : t
val interface_default : t
val interface_call : string -> t

(** [method_two a b name found]: two interfaces give a method of that name to a value that meets both. *)
val method_two : string -> string -> string -> string -> t

(** [wrong_type fname name want found]: a value of the wrong type for a parameter or a field. *)
val wrong_type : string -> string -> string -> string -> t

(** [wrong_result fname want found]: a value of the wrong type for the return type of a function. *)
val wrong_result : string -> string -> string -> t

(** The name with its article: [an Int], [a Point]. *)
val article : string -> string
val destructure_array : int -> int -> t
val destructure_struct : string -> t
val destructure_value : string -> t
val index_count : t
val it_assign : t
val no_match : string -> t
val assertion : t
val use_nested : t
val use_cycle : t

(** [use_quoted path]: the hint shows that path from the root. *)
val use_quoted : string -> t

val use_relative : t
val use_empty : string -> t

(** [use_same name other line]: two uses of a file give one name. *)
val use_same : string -> string -> int -> t

(** [use_both name folder]: a package named like a module of the binary. *)

val use_missing : string -> t

(** [use_std name]: [use csv], [use pkg/csv] or [use sys], written before std/. [use_path name folder]: [use shapes] for a
    folder of the project, whose use is its path from the root. *)
val use_std : string -> t
val use_path : string -> string -> t

(** [source_missing dir], [source_outside dir]: a folder of [src] in cesia.toml. *)
val source_missing : string -> t

val source_outside : string -> t

(** [cesia_needed needed this]: [cesia = "0.3"] in cesia.toml, read by Cesia [0.2.0]. *)
val cesia_needed : string -> string -> t

(** What [cesia] in cesia.toml holds, for {!project_type}. *)
val cesia_not_version : string

(** [changed_by_hand path], [not_installed folder]: a file of std/ or deps/ against cesia.lock. *)
val changed_by_hand : string -> t

val not_installed : string -> t

(** [use_dep upath]: [use deps/x/y], with no package. *)
val use_dep : string -> t
val no_name : string -> string -> t
val exit_code : string -> t
val denied : string -> string option -> t

val reload_use : t
val use_unreadable : string -> t
val range_too_long : t
val no_on_stop : t
val no_main : t
val bad_answer : string -> t
val need_text : string -> string -> t
val empty_array : string -> t

(** The texts of the command line. *)
val usage : string
val cant_read : string -> string
val unknown_permission : string -> string
val invalid_permission : string -> string
val invalid_size : string -> string
val invalid_limit : string -> string
val invalid_seed : string -> string
val unknown_limit : string -> string
val internal : string -> string

(** The texts of the reader of cesia.toml. *)
val toml_utf8 : string
val toml_control : string
val toml_unsupported : string -> string
val toml_strings_only : string
val toml_expected : string -> string
val toml_string_open : string
val toml_array_open : string
val toml_escape : char -> string
val toml_twice : string -> string

(** The texts of cesia do. *)
val at_line : int -> string -> string
val project_no_file : string
val project_no_name : string
val project_no_task : string
val project_table : string -> string
val project_outside : string -> string
val project_field : string -> string -> string
val project_type : string -> string -> string -> string
val project_empty_run : string -> string
val project_both : string -> string
val project_without_file : string -> string -> string
val project_missing : string -> string -> string
val project_cycle : string -> string list -> string
val project_listed_needs : string list -> string
val project_bad_name : string -> string
val project_exists : string -> string
val project_created : string -> string
val project_no_such_task : string -> string
val project_cant_start : string -> string -> string

val need_count : string -> string -> t
val cant_sort : string -> string -> t
val need_char : string -> t
val need_byte : string -> t
val doc_missing : string -> string

(** [doc_moved name p]: cesia doc of a name of std/p written without its package, as Map for list.Map. *)
val doc_moved : string -> string -> string
val json_value : string -> t
val column_sizes : int -> int -> t
val need_groups : string -> t
val json_at : string -> int -> string
val json_unexpected : string
val json_short_escape : string
val json_hex_escape : string
val json_surrogate : string
val json_open_text : string
val json_bad_escape : string
val json_control : string
val json_digits : string
val json_large : string
val json_deep : string
val json_no_value : string
val json_no_comma_array : string
val json_key : string
val json_colon : string
val json_no_comma_object : string
val json_after : string
val regex_bad : string -> t
val process_ended : t
val need_process : string -> string -> t
val input_closed : t
val dict_key : string -> t
val dict_absent : string -> t
val dict_index : t
val dict_pair : string -> t
val need_dict : string -> string -> t
val map_of_struct : string -> string -> t

val pattern_mismatch : string -> string -> t
val question_file : t
val question_space : t
val question_value : string -> t
val need_task : string -> t
val empty_text : string -> t
val need_array : string -> string -> t
val c_no_library : string -> string -> t
val c_no_function : string -> t
val c_type : string -> t
val c_void_arg : t
val c_too_many : int -> t
val c_no_ffi : t
val c_bad_signature : t
val c_need_struct : string -> t
val c_small_block : int -> int -> t
val c_need_callback : string -> t
val c_need_function : string -> t
val c_struct_empty : t
val c_struct_field : string -> t
val c_field_index : int -> int -> t
val c_need_layout : string -> string -> t
val c_variadic_type : string -> t
val c_callback_type : string -> t
val c_need_library : string -> t
val c_version : string -> t
val c_fit : string -> string -> t
val c_return_fit : string -> t
val c_need_integer : string -> string -> t
val c_need_number : string -> string -> t
val c_need_bool : string -> t
val c_need_ptr : string -> t
val c_need_text : string -> t
val c_size : string -> t
val c_offset : int -> int -> string -> t
val c_need_offset : string -> t
val c_block_type : string -> string -> t
val c_need_block : string -> string -> t
val c_need_pointer : string -> t
val c_freed : t
val c_no_open_library : t
val c_zero_byte : t
val bad_duration : string -> string -> t
val io_failure : string -> string -> string -> t
val need_socket : string -> string -> t
val need_port : string -> t
val socket_closed : t
val too_many_sockets : t
val server_stopped : t
val bad_char : string -> t
val need_size : string -> string -> t
val deadlock : t
val rows_same_key : string -> string -> string -> t
val rows_cells : int -> int -> t
val sql_zero_byte : string -> t
val sql_need_handle : string -> string -> string -> t
val sql_closed : t
val sql_store_directory : t
val sql_plugin : string -> t
val sql_no_statement : t
val sql_statements : t
val sql_bad_param : int -> string -> t
val sql_param_count : int -> int -> t
val sql_batch : string -> t
val sql_int_past : string -> t
val need_channel : string -> string -> t
val bad_timeout : string -> t
val receive_timeout : t
val sql_db_closed : t
val sql_pool : float -> t
val sql_pool_size : string -> t
val sql_uri : string -> t
val c_sqlite : string -> t
