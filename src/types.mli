(** The types of the engine. They form one recursive knot, so they live together. *)

type kind = Syntax | Name | Type | Index | Field | Overflow | Permission | User
type perm = Read | Write | Net | Exec | Env | Ffi | Debug

(** Bottom, integer, float, float array, anything. *)
type ty = TBot | TI | TF | TFA | TA

type t =
  | Missing
  | Undef  (** never visible to the program *)
  | True
  | False
  | Int of int
  | Float of float
  | Text of string
  | Array of arr
  | Struct of { shape : shape; fields : t array; mutable r_owned : bool }
  | Fun of { proto : proto; env : t array }
  | Native of native
  | Handle of { kind : string; id : int; task : task option }  (** a reference to something outside the values *)
  | Dict of dict

and dict = Leaf | Node of { l : dict; k : t; v : t; r : dict; h : int; n : int }
and task = { mutable result : t option; mutable waiters : (unit -> unit) list }

and arr = { rows : int; cols : int; mutable store : store; mutable a_owned : bool }
and store = F of floatarray | V of t array

and shape = {
  sid : int;
  names : string array;
  sname : string option;
  next : (string, shape) Hashtbl.t;
}


and proto = {
  pname : string;
  mutable file : int;
  pm : int;  (** the module *)
  mutable func : Ast.func;
  mutable versions : version list;
  mutable generic : version option;
  mutable by_tag : (int * version) list;  (** real type tag to version *)
  mutable arity : int;
  mutable last : last_call;  (** the last version chosen: a single word, replaced at once *)
}

and last_call = No_call | Last of { ltag : int; lver : version }


and version = {
  owner : proto;
  sg : ty array;
  mutable ret : ty;
  mutable size : int;
  mutable rv : ctx -> t;
  mutable ri : ctx -> int;
  mutable rf : ctx -> float;
  mutable slots : slot array;
  mutable state : int;  (** inference: 0 to do, 1 in progress, 2 done *)
  mutable tv : ty array;  (** the type of each variable *)
  mutable tn : ty array;  (** the type of each node *)
  mutable map : int array;  (** the slot of each variable in its stack *)
  mutable frame : int;  (** the entries taken by the variables and links *)
  mutable pk : int array;  (** each parameter: slot * 4 + stack (0 v, 1 i, 2 f) *)
}

and slot = {
  vname : string;
  sty : ty;
  at : int;
  cell : int;  (** a file variable stored in its module: its cell, else -1 *)
}

and native = {
  nname : string;
  perm : perm option;
  params : string array;
  min_args : int;
  max_args : int;
  ret_ty : ty array -> ty;
  run : ctx -> t array -> t;
  f1 : (float -> float) option;
  i2 : (ctx -> int -> int -> int) option;  (** fast path of div and mod *)
}

and ctx = {
  mutable v : t array;
  mutable f : floatarray;
  mutable i : int array;
  mutable b : int;
  mutable cap : int;
  mutable fuel : int;
  mutable refill : int;  (** the last refill of [fuel] *)
  mutable until : int;  (** the steps before the next full checkpoint *)
  mutable site : int;
  mutable again : bool;  (** tail recursion: the function must loop again *)
  max_depth : int;
  fiber : bool;  (** a spawned fiber, as opposed to the main program *)
  w : world;
}

and site = {
  sfile : int;
  spos : Pos.t;
  sfn : string;
  sver : version option;
  soff : int;  (** at this site, the v stack is dead beyond b + soff *)
  slive : Bytes.t;  (** with --debugger: the variables surely assigned before this statement *)
}

and modul = {
  mname : string;
  path : string;
  mutable cells : t array;
  mutable mnames : (string * int) list;
  mutable stable : bool array;  (** cell never reassigned: function or native *)
}

and stop_mode =
  | Starting  (** before the first statement *)
  | Running
  | Stepping
  | Until of int  (** stop at the given depth, or less *)

and debug = {
  mutable mode : stop_mode;
  mutable stopped : bool;  (** a stop doesn't trigger another one *)
  mutable breaks : (string * int) list;
  mutable on_stop : t;
  mutable last_file : int;
  mutable last_line : int;
}

and limits = { steps : int; memory_words : int; max_depth : int; nesting : int }
and grants = { all : bool; perms : (perm * string option) list }

and sched = {
  ready : (unit -> unit) Queue.t;  (** the jobs of the fibers ready to run, in order *)
  mutable next_id : int;
  mutable jobs : int;  (** the jobs run so far: I/O is polled every so often, even under load *)
  mutable current : ctx option;  (** the running fiber *)
}

and world = {
  mutable modules : modul array;
  files : (string * string) Dynarray.t;  (** displayed path, source *)
  sites : site Dynarray.t;
  shapes : (string array, shape) Hashtbl.t;
  limits : limits;
  grants : grants;
  no_spec : bool;
  hooks : bool;  (** a debugger is present: the program's files have hooks *)
  debugger : string option;
  debug : debug;
  mutable on_hook : ctx -> int -> unit;  (** set by [Loader], so that [Compile] doesn't know [Debug] *)
  mutable hook_count : int;  (** the compiled hooks *)
  sched : sched;
  mutable idle : bool -> bool;
      (** wakes what is ready, and [true] blocks until something is; returns false if nothing ever will *)
  mutable native_modules : (string * (string * t) list) list;  (** what [use] finds before std/ *)
  mutable yield : ctx -> unit;  (** set by [Loader]: gives way to the other fibers at a full checkpoint *)
  mutable on_panic : ctx -> exn -> unit;  (** set by [Loader]: reports the panic of a fiber *)
  out : Buffer.t;
  sink : string -> unit;
  err : string -> unit;
  period : int;  (** the steps between two checkpoints *)
  mutable steps_left : int;
  mutable big_words : int;
  mutable on_checkpoint : ctx -> unit;
  mutable compile_ver : ctx -> version -> unit;  (** set by [Compile], to break the cycle with [Infer] *)
  charge : ctx -> int -> unit;  (** [Runtime.charge], for [Value], which doesn't know [Runtime] *)
  loaded : (string, int) Hashtbl.t;  (** path to module, -1 while loading *)
  mutable entry_dir : string;  (** a relative [use] can't leave it without --allow read *)
}
