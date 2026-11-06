(** The types of the engine. They form one recursive knot, so they live together. *)

type kind = Syntax | Name | Type | Index | Field | Math | Permission | User
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
  | Dict of { keys : keys; vals : t array; mutable d_owned : bool }
      (** a map. Up to 32 keys it is one block: [keys] and [vals] in the order of insertion, and the [deep] of [keys] is
          [Flat]; the maps made at one place of the code share [keys]. Past them, the keys are in the trie of the [deep] of
          [keys], whose arrays are empty, as [vals]. [d_owned]: nothing else holds the map, a write may change it in
          place. *)
  | Bound of { g : t; self : t }  (** a method and its object, on their way to the call: never visible to the program *)

(** Keys and their hashes. The arrays can be longer than a map that holds them, whose keys are as many as its values: a place,
    once written, never changes, and [used] is the most places written, so that a map of [used] keys alone may write the next
    one in place, as [Append] does for lists. Keys made whole, of a literal, a native or a JSON object, have [used] =
    [max_int]: they never grow in place, and every map that holds them has all of them, so a read can cache them. *)
and keys = { ks : t array; hs : int array; mutable used : int; deep : deep }

and deep =
  | Flat  (** the keys of a block *)
  | Deep of { mutable root : node; mutable size : int; mutable next : int; mutable order : t array; ded : int }
      (** [next]: the rank of the next key; [order]: the keys and values in the order of insertion, k1 v1 k2 v2..., or
          [Trie.no_order] until asked; [ded]: the mark of the nodes that this map made, which it may change in place while
          it is owned *)

(** A node of the trie, at a level: the keys under it agree on the first 5 bits of hash of each level above. The mark of the
    map that made it: no other map changes it in place. *)
and node =
  | Block of { mutable kv : t array; mutable hr : int array; bed : int; mutable bn : int }
      (** [bn] keys: [kv] holds k1 v1 k2 v2..., [hr] each rank * 2^30 + hash; the arrays can be longer, room for the owner's
          next keys *)
  | Branch of { bits : int; kids : node array; ed : int }  (** a kid for each value of the next 5 bits of hash set in [bits] *)
  | Same of dict  (** keys whose 30 bits of hash are all equal: a balanced tree, which no choice of keys slows down *)

and dict = Leaf | Node of { l : dict; k : t; v : t; r : dict; hr : int; n : int }  (** [hr]: the rank of the key * 64 + the height *)
and task = { mutable result : t option; mutable waiters : (unit -> unit) list; items : t Queue.t }
(** A task, or a channel: its [items] in the order they were sent, and its [waiters] the receivers parked on it. *)

(** A list that Append made can have free cells behind its last one, so a store can be longer than [rows * cols]. Read its
    cells through [rows] and [cols], and call [Value.trim] before reading a store as a whole. [a_tip]: no push went on from
    this array yet, so the free cells are still free. *)
and arr = { rows : int; cols : int; mutable store : store; mutable a_owned : bool; mutable a_tip : bool }
and store = F of floatarray | V of t array | I of int array

and shape = {
  sid : int;
  names : string array;
  sname : string option;
  sm : int;  (** the module that declares this struct, whose methods it has; -1 for the others *)
  next : (string, shape) Hashtbl.t;
  mutable checks : check option array;  (** the type of each field, for the writes; empty when none has one *)
}

(** A type written in the code: [accept] gives the value, a Float for an Int that a Float wants, or [Undef] when it doesn't
    fit; [wrong] says, for a value that doesn't, what was wanted and what was found: "a Text or missing", "an Int". *)
and check = { accept : t -> t; wrong : t -> string * string }


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
  mutable call_off : int;  (** the highest base of a direct call's frame, from this one's: native code counts with it *)
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
  gives_result : bool;  (** gives an Ok or an Err, which [cesia check] wants handled *)
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
  id : int;  (** the number of the fiber, 0 for the main program *)
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
  host : int;  (** the first module of the package whose private names this one sees *)
  mutable package : int array;  (** the modules of its files, in the order of their names, then those of its natives *)
  mutable uses : int list;  (** the first module of each package its file uses *)
}

and stop_mode =
  | Starting  (** before the first statement *)
  | Running
  | Stepping
  | Until of int  (** stop at the given depth, or less *)

and debug = {
  mutable mode : stop_mode;
  mutable stopped : bool;  (** a stop doesn't trigger another one *)
  mutable breaks : (string * int * string) list;  (** file, line and condition, empty for none *)
  mutable on_stop : t;
  mutable last_file : int;
  mutable last_line : int;
  mutable test : ctx -> int -> string -> bool;  (** is a condition true at a site: set by [Eval] *)
  mutable scope : int list;  (** the modules of the code run at the prompt, the last first *)
  mutable typed_uses : (string * string) list;  (** the uses written at the prompt: alias and path *)
  mutable main : string;  (** the path of the main file *)
  made : (string, t) Hashtbl.t;  (** code run in frames, made once as a function of their variables *)
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
  repl : bool;  (** cesia run --repl: a prompt runs beside the program *)
  debug : debug;
  mutable on_hook : ctx -> int -> unit;  (** set by [Loader], so that [Compile] doesn't know [Debug] *)
  mutable hook_count : int;  (** the compiled hooks *)
  sched : sched;
  mutable idle : bool -> bool;
  mutable timer : float -> (unit -> unit) -> unit;  (** set by the system: calls a function after so many seconds *)
      (** wakes what is ready, and [true] blocks until something is; returns false if nothing ever will *)
  mutable native_modules : (string * (string * t) list) list;  (** what [use] finds before std/ *)
  mutable yield : ctx -> unit;  (** set by [Loader]: gives way to the other fibers at a full checkpoint *)
  mutable on_panic : ctx -> exn -> unit;  (** set by [Loader]: reports the panic of a fiber *)
  mutable on_error : ctx -> string -> unit;  (** with a debugger: a panic stops there, before it leaves *)
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
  methods : (int * string * string, t * bool) Hashtbl.t;
      (** module, struct or interface, and method name to the function, and whether it is static *)
  interfaces : (int * string, Ast.iface) Hashtbl.t;  (** the first module of a package, and a name, to its interface *)
  mutable reloads : int;  (** what a type found about an interface holds until the next reload *)
  mutable root : string;  (** where every [use] of the project starts *)
}
