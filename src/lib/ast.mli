(** The syntax tree. One tree travels through the whole chain: [Resolve] fills in the [binding]s. *)

type pos = Pos.t

type binding =
  | Unresolved
  | Local of int  (** variable of the function *)
  | Cell of { m : int; k : int; stable : bool }  (** module cell; stable = never reassigned *)

type name = { text : string; mutable b : binding }
type binop = Add | Sub | Mul | Div | Pow | Eq | Ne | Lt | Le | Gt | Ge

type expr = { id : int; pos : pos; mutable e : node  (** [Resolve] rewrites r.name into a variable *) }

and node =
  | Lint of int
  | Lfloat of float
  | Lbool of bool
  | Lmissing
  | Ltext of string
  | Interp of part array
  | Var of name
  | Bin of binop * expr * expr
  | Neg of expr
  | Not of expr
  | And of expr * expr
  | Or of expr * expr
  | Call of call
  | Assign of name * expr
  | If of expr * block * block
  | While of { cond : expr; body : block; has_break : bool }
  | Break
  | Return of ret
  | Lambda of func
  | Fn_def of name * func  (** named function *)
  | Range of expr * expr  (** a:b *)
  | In_op of expr * expr
  | Array_lit of expr array array  (** rows *)
  | Comp of { cbody : expr; cvar : name; csrc : expr; cguard : expr option }  (** comprehension *)
  | Index of expr * index array * bool  (** the boolean: an index uses [end] *)
  | Field of expr * string
  | Struct_lit of { sname : string option; sfields : (string * expr) array }
  | End_index  (** [end] in an index *)
  | For of { var : name; iter : expr; fbody : block; f_break : bool }
  | Set of { root : name; path : step array; value : expr }  (** write to a path *)
  | Destructure of pat * expr
  | Match of { subject : expr; arms : arm array }
  | Use of { upath : string; ualias : string }
  | Interface of iface  (** at the top of a file *)
  | Question of expr  (** e? *)
  | Hook of hook  (** debugger hook: only exists with --debugger *)

and hook = { mutable live : Bytes.t  (** per variable: surely assigned before this statement *) }
and index = All | Ix of expr
and arm = { pt : pat; guard : expr option; abody : expr }

and pat =
  | Pname of name
  | Pwild
  | Plit of expr
  | Parray of pat array
  | Pstruct of (string * pat) array
  | Pcons of cons  (** a named struct: Point(x, y), or geo.Point(x, y) for one of another package *)

and cons = { cpkg : string option; cname : string; cargs : pat array  (** its fields in order *); cpos : pos }

and step = { sp : pos; sk : step_kind }
and step_kind = Sindex of index array * bool | Sfield of string

and call = { callee : expr; args : arg array; mutable self_tail : bool  (** direct tail recursion *) }
and ret = { rvalue : expr option; mutable tail : bool  (** in tail position: costs nothing *) }
and block = expr array
and part = Lit of string | Hole of expr
and arg = { aname : string option; value : expr }
and param = { pname : string; default : expr option; ptype : ptype option }

(** An interface: its name, and each of its methods with its parameters, whose number alone counts, and its return type. *)
and iface = { iname : string; imethods : (string * param array * ptype option) array }

(** A type written after a parameter, a field or the parameters of a function: a kind, as [Int], or a struct or an
    interface, [Point] or [geo.Point], which [Resolve] binds. [topt]: it ends with [?] and also takes [missing]. *)
and ptype = { tpos : pos; tpkg : string option; tname : string; topt : bool; mutable tb : binding }

and func = {
  fname : string;
  params : param array;
  ret : ptype option;  (** the return type *)
  body : block;
  nnodes : int;
  fpos : pos;
  mutable nvars : int;
  mutable var_names : string array;
  mutable captures : (int * int) array;  (** enclosing variable, local variable *)
  mutable maybe_undef : bool array;  (** variable that can be read before any assignment *)
  mutable has_return : bool;  (** contains a [return] that is not in tail position *)
  mutable has_self_tail : bool;
  mutable kept : int;  (** bit k: parameter k is written, reassigned or returned, so it can't be lent *)
  mutable cell_of : int array;  (** file only: variable to cell, -1 if it stays local *)
  mutable export_of : int array;  (** file only: variable to its export cell *)
}

(** What [Resolve] returns for a file. *)
type layout = {
  cell_names : string array;  (** the names of the module's cells, by index *)
  hoisted : (int * func) array;  (** cell, hoisted function *)
  methods : (string * string * bool * int) list;  (** struct or interface, method name, static, cell *)
  interfaces : (int * iface) list;  (** cell, interface *)
}
