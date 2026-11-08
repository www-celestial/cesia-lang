(** The JIT's IR: the blocks of a version, typed, made by [Lower] and written as MIR by [Mirtext].

    An int register holds 2n for the Cesia integer n, so that the processor's flag of 64-bit overflow tells exactly the
    63-bit overflow of OCaml's integers; a slot of the int stack holds 2n + 1, an OCaml integer. A float register holds a
    double. A value register holds an OCaml value, a word of [Types.t]: native code never holds one across anything that
    can collect, as nothing collects inside a run (allocations take room reserved before, see [Reserve]). *)

type kind = Kint | Kfloat | Kval

(** An operand: a register, or a constant (a Cesia integer, written 2n by [Mirtext], a finite float, or a word written as
    it is, a value that is no block: [missing], [true], [false]). *)
type value = Reg of int | Int of int | Float of float | Word of int

(** What [Unbox] takes: [Number] an Int or a Float, as a float; [Only_float] a Float; [Only_int] an Int. Anything else
    bails. *)
type unbox = Number | Only_float | Only_int

type cmp = Eq | Ne | Lt | Le | Gt | Ge

(** [Add], [Sub], [Mul], [Div], [Mod] on integers, checked as the interpreter checks them; [Div] and [Mod] as Cesia's
    natives of those names. The others on floats; [Fpow] is C's [pow], as OCaml's [**]. *)
type op = Add | Sub | Mul | Div | Mod | Fadd | Fsub | Fmul | Fdiv | Fpow

type ins =
  | Move of int * value
  | Incr of int  (** an integer register plus 1, unchecked: a loop's counter below its bound *)
  | Op of op * int * value * value * int
      (** the destination, the operands, the site of an error; -1 for an integer [Add] or [Sub] whose operands' bounds
          prove it can't overflow, then unchecked *)
  | Neg of int * value * int
  | Fneg of int * value
  | Float_of of int * value
  | Math of string * int * value  (** a function of C's libm: sqrt, exp, log, sin, cos, tan, asin, acos, atan, fabs *)
  | Len of int * int  (** the number of cells of an array, by its number in [arrays] *)
  | Dim of int * int * int  (** [Dim (r, a, d)]: the size of dimension [d], from 0, of an array that takes an index per dimension *)
  | Elem of int * int * value * int  (** the destination, the array, the index from 1, the site *)
  | Set_elem of int * value * value * int  (** the array, the index from 1, the value, the site *)
  | Call of int * int * value array * int * int
      (** the destination, the function of the unit, the arguments, the site, and the statement of a region's loop that
          the run bails to, its fuel as at its start, when the call wants a longer stack, or -1: the run then stops *)
  | Tick of int * bool * int
      (** one step of fuel. When it runs out at a tick that can leave (outside any loop, or that of a loop in no other), the
          run leaves and comes back at the resume point; inside an inner loop, or in a nested frame, it takes another
          quantum, and when a full checkpoint is due it asks the next tick that can leave to do so: a full checkpoint then
          waits at most for that inner loop. The last, a site whose inlined frames end with the one whose step it is, or
          -1 for the function's own: where the limit of steps, reached there, names the frame *)
  | Try of op * int * value * value * int  (** [Add], [Sub] or [Mul] that goes to the block on overflow, raising nothing *)
  | Elem_at of int * int * int
      (** the destination, the array, a register of its index from 1, doubled as every integer register, proved inside *)
  | Set_at of int * int * value  (** the array, a register of its index proved inside, the value *)
  | Offset of int * int * value array * int * bool
      (** [Offset (r, a, ixs, site, write)]: in [r], the cell of these integer indexes, one per dimension of array [a], from
          1 and doubled as an index of [Elem_at]; each is checked inside its size, and one outside is the interpreter's
          error of a read, or of a write when [write], at the site *)
  | Bump of int * value  (** an integer register plus a value, unchecked: an index that a loop moves by its step *)
  | Burn  (** one step of fuel, unchecked: a loop that proved it has the fuel for all its steps *)
  | Frame of int * int
      (** [Frame (r, base)]: [r], a raw integer, the base a callee of the frame at [base] takes: a register of a raw base,
          or -1 for the function's own frame *)
  | Enter of int * int * int * int
      (** [Enter (r, base, site, k)]: an inlined callee enters its frame at [r], called at [site] from the frame at
          [base]: the depth and the stack are checked as for a call, and where the stack would be short, the run bails
          to statement [k] as [Call] does, or stops at -1 *)
  | Enter_or_bail of int * int
      (** [Enter_or_bail (r, k)]: the same, for a struct's function; when it can't, the run bails before statement [k],
          and the interpreter makes the call *)
  | Unbox of int * value * unbox * int
      (** [Unbox (r, v, how, k)]: the number in the value [v]; else the run bails before statement [k] of its loop *)
  | Box of int * value  (** a value made of an integer or a float operand: an Int or a Float, in reserved room *)
  | Share of value  (** a list, struct or map stored elsewhere: it is no longer owned, as [Value.share] *)
  | Vals of int * value * int * int * int
      (** [Vals (r, m, c, f, k)]: the values of the map [m] whose keys are those of the constant [c], in a store of
          floats ([f] 0) or of values (1); else the run bails before statement [k] *)
  | Fields of int * value * int * int * int
      (** [Fields (r, s, sid, f, k)]: the fields of the struct [s] of shape [sid], in a store of floats ([f] 0) or of
          values (1); else bails *)
  | Load of int * int * int * int
      (** [Load (r, a, i, k)]: cell [i] of those values or fields, a double when [r] is a float register; with [k] >= 0,
          when there are that many, else bails *)
  | Get of int * int * value * int  (** a cell of an array of values: the destination, the array, the index, the site *)
  | Put of int * value * value * int  (** the array of values, the index, the value, the site, through the write barrier *)
  | Record of int * int * int * value array
      (** [Record (r, tag, c, vals)]: a new owned map ([tag] 8) or struct ([tag] 4), its keys or shape those of the
          constant [c], in reserved room: its values in an F store when they are all floats, else in a V *)
  | Into of int * value * value array * int * int * int * (int * int) option * int
      (** [Into (a, i, xs, c, tag, site, seen, back)]: a map ([tag] 8) of the keys of the constant [c], or a struct (4)
          of its shape, of the doubles [xs], written at index [i] of the array of values [a]: in place, into the one
          there when it is owned, of those keys or that shape and of floats, so nothing else sees it; else, with [back]
          >= 0, the run bails to that statement with its fuel as at its start, as [Call] does, and the interpreter makes
          the write ([io_code] then [Ir.written]); with -1, a new one, in reserved room, through the write barrier.
          [seen]: the registers of the one there and of its doubles, read and checked in this turn, when nothing wrote
          the array since *)
  | Keep of int * int * int  (** the fuel, and the steps spent and the quantum of nested frames, at a statement's start *)
  | Reserve of int ref * int
      (** room for so many words of allocation before the next [Reserve]; when the young heap lacks it, the run leaves
          at the resume point, the interpreter's allocation collects, and the run comes back *)

type term =
  | Jump of int
  | Branch of cmp * kind * value * value * int * int  (** if a cmp b then the first block else the second *)
  | Return of value
  | Done  (** the end of a loop run natively: every variable back in its slot, and the interpreter goes on after the loop *)
  | Out of value  (** a [return] inside such a loop: the function ends with that value *)
  | Fuel_ge of value * int * int  (** to the first block if the fuel left is at least that integer, else the second *)
  | Room of int * int * int
      (** [Room (r, yes, no)]: to [yes] if a frame at base [r] is under the limit, with no slow check, and the fuel has a
          step left, else to [no] *)
  | Is_fun of value * int * int * int  (** to the first block if the value is a function of the constant's code, else the second *)
  | Bail of int  (** the run bails before that statement *)

type block = { mutable ins : ins list;  (** in order *) mutable term : term }

(** A variable kept in a register, and its slot in the stack of its kind, from the base of the frame. *)
type var = { reg : int; kind : kind; slot : int }

type func = {
  name : string;
  params : var array;
  result : kind;
  vars : var array;  (** every variable in a register, the parameters and the loop counters included *)
  arrays : (int * bool * int * int) array;
      (** each array: its slot in the value stack, whether the code writes it, its store, 0 floats or 1 values, and the
          indexes it takes when it takes more than one, as many as its dimensions: then its sizes are checked and read at
          each entry; 0 when it takes one only *)
  consts : Types.t array;
      (** values whose first field native code reads, the keys of a map or the shape of a struct: written by [Engine] to
          the value slots from [frame] before each run *)
  keeps : (int * int * int) array;  (** for each statement of a region's loop, the registers of its [Keep] *)
  loose : bool;
      (** a call that wants a longer stack stops the run, which then has to start again: such a run may not write *)
  restores : (int * int) list array;
      (** for each statement of a region's loop, the registers of the variables it assigns and of their copies at its
          start: a guard after such an assignment bails to [restored] + the statement, which puts them back first *)
  kinds : kind array;  (** of each register *)
  blocks : block array;  (** block 0 comes first *)
  resumes : int array;  (** the block of each resume point *)
  frame : int;  (** the slots of the version's frame *)
  size : int;  (** the stack the frame needs from its base; a call's frame starts at [frame + hidden] *)
  hidden : int;  (** int slots after [frame] for loop counters and bounds *)
  sites : int array;  (** the sites, numbered in the world, that [Op], [Elem], [Call]... name by their index here *)
  pure : bool;  (** writes no array: a run that stops for want of stack can start again *)
  calls : bool;
  spills : bool;  (** with a debugger: an error writes the variables back to their slots, for the stop *)
  chains : (int * int * int) list array;
      (** for each site, the inlined frames it is in, the innermost first: the register of the frame's base, its caller's
          base (-1 for the function's own frame) and the site of the call. An error there writes their links. *)
  stride : int;
  need : int;
      (** the interpreter's frames for its calls, inlined or not: the highest base of one from the frame making it, and the
          largest such frame; [-1] when unknown. Under a limit of memory, native frames ask for the stack these would. *)
  numbers : (var * int) array;
      (** a region's variables of no type whose value crosses from one iteration to the next, that held a number when it
          lowered: each kept as an integer or a float for the whole run, in a hidden slot of its stack (also in [vars]),
          and its value slot. [Engine] unboxes them there before a run and boxes them back after one that wrote its
          variables: a step pays no box *)
  lent : int array;
      (** the registers of value variables that may hold a value read from a list, a map or another variable: marked
          shared when the run writes them back, not at each read *)
  sunk : (int * int * Types.t) array;
      (** the variables kept as the values of a map or struct of floats that the run never makes: the first of the
          hidden float slots of its values, its value slot, and a map of its keys or a struct of its shape, without
          values. [Engine] puts the values there before a run, from the map or struct the slot holds, which must be of
          those keys or that shape and of floats, and makes a new one of them after a run that wrote its variables *)
}

(** The frame of a call made from the outermost native frame starts [frame + hidden] above its base; a call from a nested
    frame starts 2 above: a nested frame holds only its link to its caller and its site, written when an error unwinds. *)

(** The cells of the [io] array of the JIT's single entry, all OCaml integers. The first three are the stacks, which the C
    glue fills; the others are copied to a context of raw integers for native code, and back. The C glue also writes, at
    [cx_young] and [cx_young + 1] of that context, the addresses of the young heap's pointer and limit. *)

let cx_young = 30

let cx_result = 29
(** The cell of that context where a function puts its result just before it returns: its one result is the fuel it
    leaves, or a negative one when it stopped, as Windows x86-64 gives a function only one. *)

let restored = 1 lsl 20

let io_base = 3
let io_entry = 4  (** 0 to start, or 1 + a resume point *)
let io_fuel = 5  (** the fuel given; after, what is left of the last quantum *)
let io_lim = 6  (** the highest base a nested frame may take before a slow check *)
let io_cap2 = 7  (** the highest base the stacks hold: their length less 2 *)
let io_depth = 8  (** the highest base the limit of depth allows *)
let io_budget = 9  (** the steps left before the limit of steps, counted from the fuel given *)
let io_spent = 10  (** the steps of the quanta that nested frames used up and refilled *)
let io_quantum = 11  (** the fuel at the start of the last quantum *)
let io_status = 12
let io_point = 13  (** the resume point, or the site of an error *)
let io_code = 14  (** the error *)
let io_a = 15  (** the operands of the error *)
let io_b = 16
let io_frame = 17  (** the base of the frame of the error *)
let io_int = 18  (** the result, when it is an integer *)
let io_until = 19  (** the steps left before a full checkpoint, counted from the fuel given *)
let io_leave = 20  (** set when a full checkpoint is due: the next tick that can leave does *)
let io_mem = 21
(** the highest base a nested frame may take before the interpreter's frames, as [stride] and [need] count them, would
    want a longer stack: under a limit of memory, native code then asks for it as the interpreter would *)

let io_ixs = 22
(** the first of [max_ixs] cells: the indexes of an error of [Offset], which takes at most that many, below [cx_result] *)

let max_ixs = 7
let io_size = io_ixs + max_ixs

(** Statuses. *)

let ok = 0
let fuel_out = 1  (** at [io_point], all variables written to their slots *)
let error = 2  (** the site in [io_point], the code in [io_code] *)
let fallback = 3  (** an array is not what the native code takes: nothing ran, run the interpreter *)
let stack_out = 4  (** a nested call needs a longer stack *)
let too_deep = 5  (** the limit of depth, at the site [io_point], for a frame at [io_frame] *)
let too_long = 6  (** the limit of steps *)
let returned = 7  (** a [return] inside a loop run natively: its value in [io_int], or in the float slot [frame] *)
let frames_out = 8
(** under a limit of memory, the interpreter's frames would want a longer stack here: the frame at [io_frame], entered at
    the site [io_point], its links written; nothing that shows was written, so the run can start again *)

let reloaded = 9  (** not native code's: a reload came at a checkpoint, and the run left at its loop's step *)

let bailed = 10
(** a guard failed before statement [io_point] of the region's loop, before anything of it showed: every variable is in its
    slot as at that statement, and the interpreter goes on from it *)

let gc = 11  (** at [io_point], all variables written to their slots: the young heap lacks [io_a] words *)

(** Codes of errors: the interpreter redoes the operation with [io_a] and [io_b] to give its message. *)

let err_add = 1
let err_sub = 2
let err_mul = 3
let err_neg = 4
let err_div = 5
let err_mod = 6
let err_read = 7  (** an index outside the array: [io_a] the index, [io_b] the array's slot *)
let err_write = 8

let err_read_nd = 9
(** an index of [Offset] outside: [io_a] the count of indexes, from cell [io_ixs] on, [io_b] the array's slot *)

let err_write_nd = 10

let written = 11
(** In [io_code] after a bail: no guess failed, the interpreter makes a write that native code left to it. *)
