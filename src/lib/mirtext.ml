open Types

type backend = {
  load : string -> string array -> nativeint array;
  call : nativeint -> int array -> floatarray -> t array -> int array -> int;
}

let backend : backend option ref = ref None

(* Each unit gets its own names: MIR's exported names are global. *)
let units = ref 0

(* A Cesia integer as a register holds it: 2n, which needs 64 bits. *)
let doubled n = Int64.to_string (Int64.mul 2L (Int64.of_int n))
let tagged n = Int64.to_string (Int64.add (Int64.mul 2L (Int64.of_int n)) 1L)

(* A float that MIR reads back exactly, and as a float. *)
let float_lit x =
  let s = Printf.sprintf "%.17g" x in
  if String.exists (fun c -> c = '.' || c = 'e') s then s else s ^ ".0"

let operand = function Ir.Reg r -> "r" ^ string_of_int r | Int n -> doubled n | Float x -> float_lit x
let ty = function Ir.Kint -> "i64" | Kfloat -> "d"
let cmp_name = function Ir.Eq -> "eq" | Ne -> "ne" | Lt -> "lt" | Le -> "le" | Gt -> "gt" | Ge -> "ge"
let flip = function Ir.Lt -> Ir.Gt | Le -> Ge | Gt -> Lt | Ge -> Le | c -> c
let io k = Printf.sprintf "i64:%d(io)" (8 * k)

(* What [io] holds, as written by native code: OCaml integers. *)
let set_io b k v = Printf.bprintf b "  mov %s, %s\n" (io k) v

let func b ~prefix ~sizes (fn : Ir.func) =
  let pr fmt = Printf.bprintf b fmt in
  let stubs = Buffer.create 256 and nstub = ref 0 in
  let stub f =
    let l = Printf.sprintf "S%d" !nstub in
    incr nstub;
    Printf.bprintf stubs "%s:\n" l;
    f stubs;
    l
  in
  let zero = match fn.result with Kint -> "0" | Kfloat -> "0.0" in
  let params = Array.map (fun (v : Ir.var) -> v.reg) fn.params in
  let is_param r = Array.mem r params in
  let spill b =
    Array.iter
      (fun (v : Ir.var) ->
         match v.kind with
         | Kint -> Printf.bprintf b "  add x0, r%d, 1\n  mov i64:%d(ints, b, 8), x0\n" v.reg (8 * v.slot)
         | Kfloat -> Printf.bprintf b "  dmov d:%d(floats, b, 8), r%d\n" (8 * v.slot) v.reg)
      fn.vars
  in
  let store_fuel b = Printf.bprintf b "  lsh x0, fuel, 1\n  add x0, x0, 1\n  mov %s, x0\n" (io Ir.io_fuel) in
  let leave b status =
    store_fuel b;
    set_io b Ir.io_status (tagged status);
    Printf.bprintf b "  ret %s\n" zero
  in
  (* An error: the interpreter remakes its message from the operands, at the site, from this frame. *)
  let error code site a bv =
    stub (fun s ->
        let tag v = match v with Ir.Reg r -> Printf.bprintf s "  add x1, r%d, 1\n" r; "x1" | Int n -> tagged n | Float _ -> "1" in
        let x = tag a in
        set_io s Ir.io_a x;
        let y = match bv with Some v -> tag v | None -> "1" in
        set_io s Ir.io_b y;
        set_io s Ir.io_point (tagged fn.sites.(site));
        set_io s Ir.io_code (tagged code);
        Printf.bprintf s "  lsh x1, b, 1\n  add x1, x1, 1\n  mov %s, x1\n" (io Ir.io_frame);
        leave s Ir.error)
  in
  (* An operand in a register, for the places MIR wants one. *)
  let in_reg k v =
    match v with
    | Ir.Reg r -> "r" ^ string_of_int r
    | _ ->
      (match k with Ir.Kint -> pr "  mov x2, %s\n" (operand v); "x2" | Kfloat -> pr "  dmov y0, %s\n" (operand v); "y0")
  in
  let arr a = Printf.sprintf "a%dd" a and len a = Printf.sprintf "a%dn" a in
  let check_index a i site code =
    let e = error code site i (Some (Int (fst fn.arrays.(a)))) in
    match i with
    | Ir.Reg r ->
      pr "  sub x0, r%d, 2\n  ubge %s, x0, %s\n" r e (len a);
      Printf.sprintf "d:-8(%s, r%d, 4)" (arr a) r
    | Int k ->
      pr "  mov x0, %s\n  ubge %s, x0, %s\n" (doubled (k - 1)) e (len a);
      Printf.sprintf "d:%d(%s)" (8 * (k - 1)) (arr a)
    | Float _ -> invalid_arg "index"
  in
  let ins = function
    | Ir.Move (r, v) -> pr "  %s r%d, %s\n" (if fn.kinds.(r) = Kint then "mov" else "dmov") r (operand v)
    | Incr r -> pr "  add r%d, r%d, 2\n" r r
    | Op (((Add | Sub) as op), r, x, y, site) ->
      let x' = in_reg Kint x in
      pr "  %s r%d, %s, %s\n" (if op = Add then "addo" else "subo") r x' (operand y);
      pr "  bo %s\n" (error (if op = Add then Ir.err_add else Ir.err_sub) site x (Some y))
    | Op (Mul, r, x, y, site) ->
      (* 2a times b is 2ab: one operand doubled, the other not. *)
      (match x, y with
       | Reg p, Int n -> pr "  mulo r%d, r%d, %d\n" r p n
       | Int n, Reg q -> pr "  mulo r%d, r%d, %d\n" r q n
       | Reg p, Reg q -> pr "  rsh x0, r%d, 1\n  mulo r%d, r%d, x0\n" q r p
       | _ -> pr "  mov x0, %s\n  mulo r%d, x0, %s\n" (operand x) r (match y with Int n -> string_of_int n | _ -> "0"));
      pr "  bo %s\n" (error Ir.err_mul site x (Some y))
    | Op (((Div | Mod) as op), r, x, y, site) ->
      let e = error (if op = Div then Ir.err_div else Ir.err_mod) site x (Some y) in
      pr "  mov x0, %s\n  rsh x0, x0, 1\n  mov x1, %s\n  rsh x1, x1, 1\n  beq %s, x1, 0\n" (operand x) (operand y) e;
      let l = Printf.sprintf "D%d" !nstub in
      incr nstub;
      if op = Div then begin
        (* Floor division: one less when the remainder isn't 0 and the signs differ. *)
        pr "  div x2, x0, x1\n  mod x3, x0, x1\n  beq %s, x3, 0\n  xor x4, x3, x1\n  bge %s, x4, 0\n  sub x2, x2, 1\n" l l;
        pr "%s:\n  addo r%d, x2, x2\n  bo %s\n" l r e
      end else begin
        pr "  mod x2, x0, x1\n  beq %s, x2, 0\n  xor x4, x2, x1\n  bge %s, x4, 0\n  add x2, x2, x1\n" l l;
        pr "%s:\n  add r%d, x2, x2\n" l r
      end
    | Op (op, r, x, y, _) ->
      let name = match op with Fadd -> "dadd" | Fsub -> "dsub" | Fmul -> "dmul" | Fdiv -> "ddiv" | _ -> "" in
      if op = Fpow then pr "  call pd2, pow, r%d, %s, %s\n" r (operand x) (operand y)
      else pr "  %s r%d, %s, %s\n" name r (in_reg Kfloat x) (operand y)
    | Neg (r, x, site) ->
      pr "  mov x0, 0\n  subo r%d, x0, %s\n  bo %s\n" r (operand x) (error Ir.err_neg site x None)
    | Fneg (r, x) -> pr "  dneg r%d, %s\n" r (in_reg Kfloat x)
    | Float_of (r, x) -> pr "  mov x0, %s\n  rsh x0, x0, 1\n  i2d r%d, x0\n" (operand x) r
    | Math (name, r, x) -> pr "  call pd1, %s, r%d, %s\n" name r (operand x)
    | Len (r, a) -> pr "  mov r%d, %s\n" r (len a)
    | Elem (r, a, i, site) -> pr "  dmov r%d, %s\n" r (check_index a i site Ir.err_read)
    | Set_elem (a, i, v, site) ->
      let m = check_index a i site Ir.err_write in
      pr "  dmov %s, %s\n" m (operand v)
    | Call (r, k, args, site) ->
      let need = stub (fun s -> leave s Ir.stack_out) in
      let up = stub (fun s -> spill s; Printf.bprintf s "  ret %s\n" zero) in
      pr "  add nb, b, %d\n" (fn.frame + fn.hidden);
      pr "  mov x0, %s\n  rsh x0, x0, 1\n  add x1, nb, %d\n  bgt %s, x1, x0\n" (io Ir.io_cap) sizes.(k) need;
      pr "  lsh x0, b, 1\n  add x0, x0, 1\n  mov i64:0(ints, nb, 8), x0\n  mov i64:8(ints, nb, 8), %s\n" (tagged fn.sites.(site));
      store_fuel b;
      pr "  call P%s%d, %sf%d, r%d, ints, floats, vals, io, nb, 0%s\n" prefix k prefix k r
        (String.concat "" (Array.to_list (Array.map (fun v -> ", " ^ operand v) args)));
      pr "  mov fuel, %s\n  rsh fuel, fuel, 1\n  bne %s, %s, 1\n" (io Ir.io_fuel) up (io Ir.io_status)
    | Tick p ->
      let out = stub (fun s -> spill s; set_io s Ir.io_point (tagged p); leave s Ir.fuel_out) in
      pr "  sub fuel, fuel, 1\n  blt %s, fuel, 0\n" out
  in
  let term = function
    | Ir.Jump l -> pr "  jmp B%d\n" l
    | Branch (c, k, x, y, yes, no) ->
      let c, x, y = match x with Ir.Reg _ -> c, x, y | _ -> flip c, y, x in
      let x = in_reg k x in
      pr "  %sb%s B%d, %s, %s\n  jmp B%d\n" (if k = Kfloat then "d" else "") (cmp_name c) yes x (operand y) no
    | Return v ->
      let v = match fn.result, v with Kfloat, Int n -> Ir.Float (float_of_int n) | _ -> v in
      pr "  ret %s\n" (operand v)
  in
  pr "%s%s: func %s, p:ints, p:floats, p:vals, p:io, i64:b, i64:entry%s\n" prefix fn.name (ty fn.result)
    (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", %s:r%d" (ty v.kind) v.reg) fn.params)));
  pr "  local i64:fuel, i64:nb, i64:x0, i64:x1, i64:x2, i64:x3, i64:x4, d:y0\n";
  Array.iteri (fun r k -> if not (is_param r) then pr "  local %s:r%d\n" (ty k) r) fn.kinds;
  Array.iteri (fun a _ -> pr "  local i64:%s, i64:%s\n" (arr a) (len a)) fn.arrays;
  pr "  mov fuel, %s\n  rsh fuel, fuel, 1\n" (io Ir.io_fuel);
  (* A slot of the int stack must hold an OCaml integer, whatever a register held before. *)
  Array.iteri (fun r k -> if k = Ir.Kint && not (is_param r) then pr "  mov r%d, 0\n" r) fn.kinds;
  let guards () =
    Array.iteri
      (fun a (slot, written) ->
         pr "  mov x0, i64:%d(vals, b, 8)\n  and x1, x0, 1\n  bne F, x1, 0\n" (8 * slot);
         pr "  mov x1, i64:-8(x0)\n  and x1, x1, 255\n  bne F, x1, 3\n  mov x2, i64:0(x0)\n";
         pr "  mov x1, i64:16(x2)\n  mov x3, i64:-8(x1)\n  and x3, x3, 255\n  bne F, x3, 0\n";
         if written then pr "  mov x3, i64:24(x2)\n  bne F, x3, 3\n";
         pr "  mov %s, i64:0(x1)\n  mov x3, i64:0(x2)\n  rsh x3, x3, 1\n  mov x4, i64:8(x2)\n  rsh x4, x4, 1\n" (arr a);
         pr "  mul x3, x3, x4\n  lsh %s, x3, 1\n" (len a))
      fn.arrays
  in
  pr "  bne R, entry, 0\n";
  guards ();
  pr "  jmp B0\nR:\n";
  Array.iter
    (fun (v : Ir.var) ->
       match v.kind with
       | Kint -> pr "  mov r%d, i64:%d(ints, b, 8)\n  sub r%d, r%d, 1\n" v.reg (8 * v.slot) v.reg v.reg
       | Kfloat -> pr "  dmov r%d, d:%d(floats, b, 8)\n" v.reg (8 * v.slot))
    fn.vars;
  guards ();
  if Array.length fn.resumes > 0 then
    pr "  sub x0, entry, 1\n  switch x0, %s\n"
      (String.concat ", " (Array.to_list (Array.map (fun l -> "B" ^ string_of_int l) fn.resumes)))
  else pr "  jmp B0\n";
  Array.iteri
    (fun l (bk : Ir.block) ->
       pr "B%d:\n" l;
       List.iter ins bk.ins;
       term bk.term)
    fn.blocks;
  Buffer.add_buffer b stubs;
  pr "F:\n";
  leave b Ir.fallback;
  pr "  endfunc\n"

let used = [ "sqrt"; "exp"; "log"; "sin"; "cos"; "tan"; "asin"; "acos"; "atan"; "fabs"; "pow" ]

(* The unit as one module: each function, and the single entry [e] of the first one. *)
let emit (fns : Ir.func array) =
  incr units;
  let prefix = Printf.sprintf "u%d_" !units in
  let b = Buffer.create 4096 in
  let pr fmt = Printf.bprintf b fmt in
  pr "m%s: module\n  export %se\n  import %s\n" prefix prefix (String.concat ", " used);
  pr "pd1: proto d, d:a\npd2: proto d, d:a, d:b\n";
  Array.iteri
    (fun k (fn : Ir.func) ->
       pr "P%s%d: proto %s, p:ints, p:floats, p:vals, p:io, i64:b, i64:entry%s\n" prefix k (ty fn.result)
         (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", %s:r%d" (ty v.kind) v.reg) fn.params))))
    fns;
  let sizes = Array.map (fun (f : Ir.func) -> f.size) fns in
  Array.iter (func b ~prefix ~sizes) fns;
  let f0 = fns.(0) in
  pr "%se: func i64, p:ints, p:floats, p:vals, p:io\n  local i64:b, i64:entry, i64:x0, %s:res%s\n" prefix (ty f0.result)
    (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", %s:r%d" (ty v.kind) v.reg) f0.params)));
  pr "  mov b, %s\n  rsh b, b, 1\n  mov entry, %s\n  rsh entry, entry, 1\n" (io Ir.io_base) (io Ir.io_entry);
  Array.iter
    (fun (v : Ir.var) ->
       match v.kind with
       | Kint -> pr "  mov r%d, i64:%d(ints, b, 8)\n  sub r%d, r%d, 1\n" v.reg (8 * v.slot) v.reg v.reg
       | Kfloat -> pr "  dmov r%d, d:%d(floats, b, 8)\n" v.reg (8 * v.slot))
    f0.params;
  pr "  call P%s0, %sf0, res, ints, floats, vals, io, b, entry%s\n" prefix prefix
    (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", r%d" v.reg) f0.params)));
  (match f0.result with
   | Kint -> pr "  add x0, res, 1\n  mov %s, x0\n" (io Ir.io_int)
   | Kfloat -> pr "  dmov d:%d(floats, b, 8), res\n" (8 * f0.frame));
  pr "  mov x0, %s\n  rsh x0, x0, 1\n  ret x0\n  endfunc\n  endmodule\n" (io Ir.io_status);
  Buffer.contents b, prefix ^ "e"
