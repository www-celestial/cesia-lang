(** All error messages, in English. *)

type t = { text : string; hint : string option }

val plain : string -> t
val invalid_utf8 : t
val unexpected_char : char -> t
val text_not_closed : t
val number_too_big : string -> t
val expected : string -> string -> t
val too_nested : t
val cant_assign : t
val break_outside : t
val undefined : string -> t
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
val field_of : string -> string -> t
val struct_nested : t
val destructure_array : int -> int -> t
val destructure_struct : string -> t
val destructure_value : string -> t
val index_count : t
val it_assign : t
val no_match : string -> t
val assertion : t
val use_nested : t
val use_cycle : t
val use_missing : string -> t
val no_name : string -> string -> t
val denied : string -> t

val reload_use : t
val use_unreadable : string -> t
val no_prelude : t
val range_too_long : t
val no_on_stop : t
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
val unknown_limit : string -> string
val internal : string -> string

val pattern_mismatch : string -> string -> t
val question_file : t
val question_space : t
val question_value : string -> t
val need_task : string -> t
val empty_text : string -> t
val need_array : string -> string -> t
val bad_sleep : string -> t
val io_failure : string -> string -> string -> t
val need_socket : string -> string -> t
val need_port : string -> t
val socket_closed : t
val too_many_sockets : t
val server_stopped : t
val bad_char : string -> t
val need_size : string -> string -> t
val deadlock : t
