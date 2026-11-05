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
  | Tick of int * bool
      (** one step of fuel. When it runs out at a tick that can leave (outside any loop, or that of a loop in no other), the
          run leaves and comes back at the resume point; inside an inner loop, or in a nested frame, it takes another
          quantum, and when a full checkpoint is due it asks the next tick that can leave to do so: a full checkpoint then
          waits at most for that inner loop. *)
  | Try of op * int * value * value * int  (** [Add], [Sub] or [Mul] that goes to the block on overflow, raising nothing *)
  | Elem_at of int * int * int
      (** the destination, the array, a register of its index from 1, doubled as every integer register, proved inside *)
  | Set_at of int * int * value  (** the array, a register of its index proved inside, the value *)
  | Bump of int * value  (** an integer register plus a value, unchecked: an index that a loop moves by its step *)
  | Burn  (** one step of fuel, unchecked: a loop that proved it has the fuel for all its steps *)
  | Frame of int * int
      (** [Frame (r, base)]: [r], a raw integer, the base a callee of the frame at [base] takes: a register of a raw base,
          or -1 for the function's own frame *)
  | Enter of int * int * int
      (** [Enter (r, base, site)]: an inlined callee enters its frame at [r], called at [site] from the frame at [base]:
          the depth and the stack are checked as for a call *)

type term =
  | Jump of int
  | Branch of cmp * kind * value * value * int * int  (** if a cmp b then the first block else the second *)
  | Return of value
  | Done  (** the end of a loop run natively: every variable back in its slot, and the interpreter goes on after the loop *)
  | Out of value  (** a [return] inside such a loop: the function ends with that value *)
  | Fuel_ge of value * int * int  (** to the first block if the fuel left is at least that integer, else the second *)

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
  pure : bool;  (** writes no array: a run that stops for want of stack can start again *)
  calls : bool;
  chains : (int * int * int) list array;
      (** for each site, the inlined frames it is in, the innermost first: the register of the frame's base, its caller's
          base (-1 for the function's own frame) and the site of the call. An error there writes their links. *)
}

(** The frame of a call made from the outermost native frame starts [frame + hidden] above its base; a call from a nested
    frame starts 2 above: a nested frame holds only its link to its caller and its site, written when an error unwinds. *)

(** The cells of the [io] array of the JIT's single entry, all OCaml integers. The first three are the stacks, which the C
    glue fills; the others are copied to a context of raw integers for native code, and back. *)

val io_base : int
val io_entry : int  (** 0 to start, or 1 + a resume point *)
val io_fuel : int  (** the fuel given; after, what is left of the last quantum *)
val io_lim : int  (** the highest base a nested frame may take before a slow check *)
val io_cap2 : int  (** the highest base the stacks hold: their length less 2 *)
val io_depth : int  (** the highest base the limit of depth allows *)
val io_budget : int  (** the steps left before the limit of steps, counted from the fuel given *)
val io_spent : int  (** the steps of the quanta that nested frames used up and refilled *)
val io_quantum : int  (** the fuel at the start of the last quantum *)
val io_status : int
val io_point : int  (** the resume point, or the site of an error *)
val io_code : int  (** the error *)
val io_a : int  (** the operands of the error *)
val io_b : int
val io_frame : int  (** the base of the frame of the error *)
val io_int : int  (** the result, when it is an integer *)
val io_until : int  (** the steps left before a full checkpoint, counted from the fuel given *)
val io_leave : int  (** set when a full checkpoint is due: the next tick that can leave does *)
val io_size : int

(** Statuses. *)

val ok : int
val fuel_out : int  (** at [io_point], all variables written to their slots *)
val error : int  (** the site in [io_point], the code in [io_code] *)
val fallback : int  (** an array is not what the native code takes: nothing ran, run the interpreter *)
val stack_out : int  (** a nested call needs a longer stack *)
val too_deep : int  (** the limit of depth, at the site [io_point], for a frame at [io_frame] *)
val too_long : int  (** the limit of steps *)
val returned : int  (** a [return] inside a loop run natively: its value in [io_int], or in the float slot [frame] *)

(** Codes of errors: the interpreter redoes the operation with [io_a] and [io_b] to give its message. *)

val err_add : int
val err_sub : int
val err_mul : int
val err_neg : int
val err_div : int
val err_mod : int
val err_read : int  (** an index outside the array: [io_a] the index, [io_b] the array's slot *)
val err_write : int
