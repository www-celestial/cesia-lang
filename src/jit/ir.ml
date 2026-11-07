type kind = Kint | Kfloat | Kval
type value = Reg of int | Int of int | Float of float | Word of int
type unbox = Number | Only_float | Only_int
type cmp = Eq | Ne | Lt | Le | Gt | Ge
type op = Add | Sub | Mul | Div | Mod | Fadd | Fsub | Fmul | Fdiv | Fpow

type ins =
  | Move of int * value
  | Incr of int
  | Op of op * int * value * value * int
  | Neg of int * value * int
  | Fneg of int * value
  | Float_of of int * value
  | Math of string * int * value
  | Len of int * int
  | Elem of int * int * value * int
  | Set_elem of int * value * value * int
  | Call of int * int * value array * int * int
  | Tick of int * bool
  | Try of op * int * value * value * int
  | Elem_at of int * int * int
  | Set_at of int * int * value
  | Bump of int * value
  | Burn
  | Frame of int * int
  | Enter of int * int * int * int
  | Enter_or_bail of int * int
  | Unbox of int * value * unbox * int
  | Box of int * value
  | Share of value
  | Vals of int * value * int * int
  | Fields of int * value * int * int
  | Load of int * int * int * int
  | Get of int * int * value * int
  | Put of int * value * value * int
  | Record of int * int * int * value array
  | Keep of int * int * int
  | Reserve of int ref * int

type term =
  | Jump of int
  | Branch of cmp * kind * value * value * int * int
  | Return of value
  | Done
  | Out of value
  | Fuel_ge of value * int * int
  | Bail of int
type block = { mutable ins : ins list; mutable term : term }
type var = { reg : int; kind : kind; slot : int }

type func = {
  name : string;
  params : var array;
  result : kind;
  vars : var array;
  arrays : (int * bool * int) array;
  consts : Types.t array;
  keeps : (int * int * int) array;
  loose : bool;
  restores : (int * int) list array;
  kinds : kind array;
  blocks : block array;
  resumes : int array;
  frame : int;
  size : int;
  hidden : int;
  sites : int array;
  pure : bool;
  calls : bool;
  spills : bool;  (* with a debugger: an error writes the variables back to their slots, for the stop *)
  chains : (int * int * int) list array;
  stride : int;
  need : int;
}

let io_base = 3
let io_entry = 4
let io_fuel = 5
let io_lim = 6
let io_cap2 = 7
let io_depth = 8
let io_budget = 9
let io_spent = 10
let io_quantum = 11
let io_status = 12
let io_point = 13
let io_code = 14
let io_a = 15
let io_b = 16
let io_frame = 17
let io_int = 18
let io_until = 19
let io_leave = 20
let io_mem = 21
let io_size = 22
let ok = 0
let fuel_out = 1
let error = 2
let fallback = 3
let stack_out = 4
let too_deep = 5
let too_long = 6
let returned = 7
let frames_out = 8
let reloaded = 9
let bailed = 10
let gc = 11
let cx_young = 30
let cx_result = 29
let restored = 1 lsl 20
let err_add = 1
let err_sub = 2
let err_mul = 3
let err_neg = 4
let err_div = 5
let err_mod = 6
let err_read = 7
let err_write = 8
