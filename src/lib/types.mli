(** The types of the engine. They form one recursive knot, so they live together. *)

type kind = Syntax | Name | Type | Index | Field | Math | Permission | User
type perm = Read | Write | Net | Exec | Env | Ffi | Native | Debug

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
  | Struct of { shape : shape; mutable fields : store; mutable r_owned : bool }
      (** a struct: its values in a store, [F] while every one is a float, [V] otherwise, as a map's *)
  | Fun of { proto : proto; env : t array }
  | Native of native
  | Handle of { kind : string; id : int; task : task option }  (** a reference to something outside the values *)
  | Dict of { keys : keys; mutable vals : store; mutable d_owned : bool }
      (** a map. Up to 32 keys it is one block: [keys] and [vals] in the order of insertion, and the [deep] of [keys] is
          [Flat]; the maps made at one place of the code share [keys]. [vals] is [F] while every value is a float (an Int
          stays an Int, in [V]), [V] otherwise, and turns from [F] to [V] once, at a write of another value. Past 32 keys,
          they are in the trie of the [deep] of [keys], whose arrays are empty, as [vals]. [d_owned]: nothing else holds
          the map, a write may change it in place. *)
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

(** A node of the trie, at a level: the keys under it agree on the 5 bits of hash of each level above. The mark of the
    map that made it: no other map changes it in place. *)
and node =
  | Champ of { mutable dmap : int; mutable nmap : int; mutable kv : t array; mutable hr : int array; mutable kids : node array; ed : int }
      (** CHAMP's node: a key whose 5 bits of hash at this level no other key under it shares is held here, its bit set in
          [dmap], in [kv] (k1 v1 k2 v2...) and [hr] (rank * 2^30 + hash) in the order of the bits; the keys of a bit that
          several share are in a node of the next level, its bit set in [nmap], in [kids] in the order of the bits. The
          arrays can be longer, room for the owner's next keys. *)
  | Same of dict  (** keys whose 30 bits of hash are all equal: a balanced tree, which no choice of keys slows down *)
  | Table of table  (** the root of a deep map that no other map ever held, never below a node *)

(** An insertion-ordered hash table, Python's compact dict: each of [tslots], a power of two at least twice the entries, is
    0 or hash * 2^32 + entry + 1, found by linear probing from hash land (size - 1); the keys [tkeys] and values [tvals] of
    the [tcount] entries in the order of insertion, [tvals] an [I] while every value is an integer. The first write that
    must keep the old map, or a probe of a new key past 128 slots, turns it into the trie, in place and for good. *)
and table = { mutable tslots : int array; mutable tkeys : t array; mutable tvals : store; mutable tcount : int }

and dict = Leaf | Node of { l : dict; k : t; v : t; r : dict; hr : int; n : int }  (** [hr]: the rank of the key * 64 + the height *)
(** What a handle of std/fiber points to. *)
and task = Job of job | Chan of chan

(** A task: its [result] once it ended, the fibers that wait for it, and its fiber while it runs. A task that ended
    lets go of its fiber, so its stacks are freed. *)
and job = {
  mutable result : t option;
  mutable waiters : (unit -> bool) list;  (** the wakes of the fibers parked until it ends *)
  mutable cx : ctx option;
}

(** A channel: its [items] in the order they were sent, at most [size] of them ([max_int]: no limit), the [receivers]
    parked on it, oldest first, and the [senders] parked while it is full. A parked fiber's wake gives false when the
    fiber had already gone, woken by something else. Once [closed], nothing more is sent. *)
and chan = {
  items : t Queue.t;
  size : int;
  mutable receivers : (unit -> bool) list;
  senders : sender Queue.t;
  mutable closed : bool;
}

(** A value that waits to go in a full channel, and the fiber that sent it: [taken] once a receiver has it. *)
and sender = { sent : t; mutable taken : bool; wake : unit -> bool }

(** A list that Append made can have free cells behind its last one, so a store can be longer than [rows * cols]. Read its
    cells through [rows] and [cols], and call [Value.trim] before reading a store as a whole. [a_tip]: no push went on from
    this array yet, so the free cells are still free. [dims]: [||] for an array of one or two dimensions, whose sizes are
    [rows] and [cols]; for three or more, the size of each, never changed, with [rows] the first and [cols] the product of
    the others, so that [rows * cols] is always the count of cells. The cells are column by column: the first index moves
    fastest. *)
and arr = { rows : int; cols : int; mutable store : store; mutable a_owned : bool; mutable a_tip : bool; dims : int array }
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
  mutable seen : (int * proto list ref) list;
      (** each call of a function held in a value in its code, by the node of the call: the functions it reached, the
          last first, at most [Compile.seen_most], on which the JIT bets *)
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
  mutable parks : int;  (** odd while parked: counts its waits and wakes, so a wake meant for an earlier wait does nothing *)
  mutable cancelled : bool;  (** fiber.Cancel asked it to stop: it does at its next wait, or now if it is waiting *)
  mutable wake : unit -> bool;  (** while a spawned fiber is parked, what queues it again; fiber.Cancel calls it *)
  w : world;
}

and site = {
  sfile : int;
  spos : Pos.t;
  sfn : string;
  sver : version option;
  soff : int;  (** at this site, the v stack is dead beyond b + soff *)
  slive : Bytes.t;  (** with --debugger: the variables surely assigned before this statement *)
  shidden : bool;  (** native code keeps the variables of this frame in registers: a stop shows none of them *)
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
  mutable stamp : int;  (** the breakpoints changed this many times: a hook knows when to look at them again *)
  mutable marked : world -> int -> bool;  (** is there a breakpoint on the line of this site: set by [Loader] *)
  mutable watches : string list;  (** the expressions a debugger shows at each stop, in order *)
  mutable test : ctx -> int -> string -> (bool, string) result;
      (** is a condition true at a site, or the error it gives: set by [Eval] *)
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
  files : (string * string) Vec.t;  (** displayed path, source *)
  sites : site Vec.t;
  shapes : (string array, shape) Hashtbl.t;
  limits : limits;
  grants : grants;
  no_spec : bool;
  hooks : bool;  (** a debugger is present: the program's files have hooks *)
  debugger : string option;
  repl : bool;  (** cesia run --repl: a prompt runs beside the program *)
  cell_session : bool;  (** cesia run --cells: the session of std/cells on a file, which runs none of it *)
  debug : debug;
  mutable on_hook : ctx -> int -> bool -> unit;
      (** set by [Loader], so that [Compile] doesn't know [Debug]: a site, and whether it is the first statement of its line *)
  mutable hook_count : int;  (** the compiled hooks *)
  sched : sched;
  mutable idle : bool -> bool;
      (** wakes what is ready, and [true] blocks until something is; returns false if nothing ever will *)
  mutable timer : float -> (unit -> unit) -> unit -> unit;
      (** set by the system: calls a function after so many seconds, and gives the function that cancels it *)
  mutable remote : (unit -> unit) -> unit -> unit;
      (** set by the system: of a wake, the function that any domain may call, once, to have the scheduler call it *)
  mutable native_modules : (string * (string * t) list) list;  (** what [use] finds before std/ *)
  mutable yield : ctx -> unit;  (** set by [Loader]: gives way to the other fibers at a full checkpoint *)
  mutable next_in : ctx -> t -> t option;
      (** set by [Loader]: the next value of a channel, waiting for it, or None once it is closed and empty: what a for
          loop over a channel takes *)
  mutable on_panic : ctx -> exn -> unit;  (** set by [Loader]: reports the panic of a fiber *)
  mutable on_error : ctx -> string -> unit;  (** with a debugger: a panic stops there, before it leaves *)
  out : Buffer.t;
  mutable sink : string -> unit;
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
