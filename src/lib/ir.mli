(** The JIT's IR: the blocks of a version, typed, made by [Lower] and written as MIR by [Mirtext].

    An int register holds 2n for the Cesia integer n, so that the processor's flag of 64-bit overflow tells exactly the
    63-bit overflow of OCaml's integers; a slot of the int stack holds 2n + 1, an OCaml integer. A float register holds a
    double. *)

type kind = Kint | Kfloat

(** An operand: a register, or a constant (a Cesia integer, written 2n by [Mirtext], or a finite float). *)
type value = Reg of int | Int of int | Float of float

type cmp = Eq | Ne | Lt | Le | Gt | Ge

(** [Add], [Sub], [Mul], [Div], [Mod] on integers, checked as the interpreter checks them; [Div] and [Mod] as Cesia's
    natives of those names. The others on floats; [Fpow] is C's [pow], as OCaml's [**]. *)
type op = Add | Sub | Mul | Div | Mod | Fadd | Fsub | Fmul | Fdiv | Fpow

type ins =
  | Move of int * value
  | Incr of int  (** an integer register plus 1, unchecked: a loop's counter below its bound *)
  | Op of op * int * value * value * int  (** the destination, the operands, the site of an error *)
  | Neg of int * value * int
  | Fneg of int * value
  | Float_of of int * value
  | Math of string * int * value  (** a function of C's libm: sqrt, exp, log, sin, cos, tan, asin, acos, atan, fabs *)
  | Len of int * int  (** the number of cells of an array, by its number in [arrays] *)
  | Elem of int * int * value * int  (** the destination, the array, the index from 1, the site *)
  | Set_elem of int * value * value * int  (** the array, the index from 1, the value, the site *)
  | Call of int * int * value array * int  (** the destination, the function of the unit, the arguments, the site *)
  | Tick of int  (** one step of fuel; if it runs out, the run leaves and comes back at the resume point *)

type term =
  | Jump of int
  | Branch of cmp * kind * value * value * int * int  (** if a cmp b then the first block else the second *)
  | Return of value

type block = { mutable ins : ins list;  (** in order *) mutable term : term }

(** A variable kept in a register, and its slot in the stack of its kind, from the base of the frame. *)
type var = { reg : int; kind : kind; slot : int }

type func = {
  name : string;
  params : var array;
  result : kind;
  vars : var array;  (** every variable in a register, the parameters and the loop counters included *)
  arrays : (int * bool) array;  (** each float array: its slot in the value stack, and whether the code writes it *)
  kinds : kind array;  (** of each register *)
  blocks : block array;  (** block 0 comes first *)
  resumes : int array;  (** the block of each resume point *)
  frame : int;  (** the slots of the version's frame *)
  size : int;  (** the stack the frame needs from its base; a call's frame starts at [frame + hidden] *)
  hidden : int;  (** int slots after [frame] for loop counters and bounds *)
  sites : int array;  (** the sites, numbered in the world, that [Op], [Elem], [Call]... name by their index here *)
}

(** The cells of the [io] array of the JIT's single entry, all OCaml integers. *)

val io_base : int
val io_entry : int  (** 0 to start, or 1 + a resume point *)
val io_fuel : int
val io_int : int  (** the result, when it is an integer *)
val io_cap : int  (** the length of the stacks *)
val io_status : int
val io_point : int  (** the resume point, or the site of an error *)
val io_code : int  (** the error *)
val io_a : int  (** the operands of the error *)
val io_b : int
val io_frame : int  (** the base of the frame of the error *)
val io_size : int

(** Statuses. *)

val ok : int
val fuel_out : int  (** at [io_point], all variables written to their slots *)
val error : int  (** the site in [io_point], the code in [io_code] *)
val fallback : int  (** an array is not what the native code takes: nothing ran, run the interpreter *)
val stack_out : int  (** a call needs a longer stack *)

(** Codes of errors: the interpreter redoes the operation with [io_a] and [io_b] to give its message. *)

val err_add : int
val err_sub : int
val err_mul : int
val err_neg : int
val err_div : int
val err_mod : int
val err_read : int  (** an index outside the array: [io_a] the index, [io_b] the array's slot *)
val err_write : int
