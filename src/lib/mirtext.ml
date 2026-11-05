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

(* A cell of the context, raw integers: the C glue copies [io] there and back. The stacks are cells 0, 1 and 2. *)
let cx k = Printf.sprintf "i64:%d(cx)" (8 * k)

(* The quantum of fuel a nested frame takes when it runs out: big, unless the limit of steps is nearer. *)
let quantum = "1099511627776"

(* The arguments every function takes before its own: the context, its base, its entry (-1 for a nested frame, 0 to start,
   1 + a resume point) and its fuel. It gives its result and the fuel left, or a negative fuel when it stopped: the status
   is then in the context, and each caller writes the link of its callee's frame as it goes up, for the trace. *)
let args_of ~nested (fn : Ir.func) =
  (if nested then "p:cx, i64:b, i64:fuel" else "p:cx, i64:b, i64:entry, i64:fuel")
  ^ String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", %s:r%d" (ty v.kind) v.reg) fn.params))

(* Each function is written twice: [f], the outermost frame, which the interpreter enters and which can leave and come
   back at a resume point; and [g], a nested frame, which only another native frame calls: no resume point, no slot
   written, a frame of 2 slots 2 above its caller's base. *)
let func b ~prefix ~nested (fn : Ir.func) =
  let pr fmt = Printf.bprintf b fmt in
  let name = if nested then "g" ^ String.sub fn.name 1 (String.length fn.name - 1) else fn.name in
  (* MIR's labels belong to the module: each function gets its own. *)
  let bl l = Printf.sprintf "%s%s_B%d" prefix name l and lf = Printf.sprintf "%s%s_F" prefix name in
  let stubs = Buffer.create 256 and nstub = ref 0 in
  let label () =
    let l = Printf.sprintf "%s%s_S%d" prefix name !nstub in
    incr nstub;
    l
  in
  let stub f =
    let l = label () in
    Printf.bprintf stubs "%s:\n" l;
    f stubs;
    l
  in
  let zero = match fn.result with Kint -> "0" | Kfloat -> "0.0" in
  let params = Array.map (fun (v : Ir.var) -> v.reg) fn.params in
  let is_param r = Array.mem r params in
  (* Only the outermost frame keeps its variables in its slots, when it leaves to come back. *)
  (* MIR has two reload registers of each class for an instruction: every memory operand here has one register for its
     address, computed first, so that an instruction never needs more, whatever was spilled. *)
  let spill b =
    Printf.bprintf b "  mov ip, %s\n  lsh xa, b, 3\n  add ip, ip, xa\n  mov fp, %s\n  add fp, fp, xa\n" (cx 0) (cx 1);
    Array.iter
      (fun (v : Ir.var) ->
         match v.kind with
         | Kint -> Printf.bprintf b "  add x0, r%d, 1\n  mov i64:%d(ip), x0\n" v.reg (8 * v.slot)
         | Kfloat -> Printf.bprintf b "  dmov d:%d(fp), r%d\n" (8 * v.slot) v.reg)
      fn.vars
  in
  let stop b status =
    Printf.bprintf b "  mov %s, fuel\n  mov %s, %d\n  ret %s, -1\n" (cx Ir.io_fuel) (cx Ir.io_status) status zero
  in
  (* The frames of inlined callees around a site: their bases, the innermost first, and the links an error writes so that
     the trace holds them, as the interpreter's frames. *)
  let reg_of base = if base < 0 then "b" else "r" ^ string_of_int base in
  let frame_of site = match fn.chains.(site) with [] -> "b" | (vb, _, _) :: _ -> reg_of vb in
  let callee_of site = match fn.chains.(site) with [] -> if nested then 2 else fn.frame + fn.hidden | _ -> 2 in
  let link s at caller csite =
    Printf.bprintf s "  mov ip, %s\n  lsh xa, %s, 3\n  add ip, ip, xa\n  lsh x0, %s, 1\n  add x0, x0, 1\n  mov i64:0(ip), x0\n" (cx 0) at caller;
    Printf.bprintf s "  mov i64:8(ip), %s\n" (tagged fn.sites.(csite))
  in
  let links s site = List.iter (fun (vb, cb, cs) -> link s (reg_of vb) (reg_of cb) cs) fn.chains.(site) in
  (* An error: the interpreter remakes its message from the operands, at the site, from this frame. *)
  let error code site a bv =
    stub (fun s ->
        let raw v = match v with Ir.Reg r -> Printf.bprintf s "  rsh x1, r%d, 1\n" r; "x1" | Int n -> string_of_int n | Float _ -> "0" in
        Printf.bprintf s "  mov %s, %s\n" (cx Ir.io_a) (raw a);
        Printf.bprintf s "  mov %s, %s\n" (cx Ir.io_b) (match bv with Some v -> raw v | None -> "0");
        links s site;
        Printf.bprintf s "  mov %s, %d\n  mov %s, %d\n  mov %s, %s\n" (cx Ir.io_point) fn.sites.(site) (cx Ir.io_code) code
          (cx Ir.io_frame) (frame_of site);
        stop s Ir.error)
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
    let raw_b = Ir.Int (fst fn.arrays.(a)) in
    match i with
    | Ir.Reg r ->
      let e = error code site i (Some raw_b) in
      pr "  sub x0, r%d, 2\n  ubge %s, x0, %s\n  lsh xa, r%d, 2\n  add xa, xa, %s\n" r e (len a) r (arr a);
      "d:-8(xa)"
    | Int k ->
      let e = error code site i (Some raw_b) in
      pr "  mov x0, %s\n  ubge %s, x0, %s\n" (doubled (k - 1)) e (len a);
      Printf.sprintf "d:%d(%s)" (8 * (k - 1)) (arr a)
    | Float _ -> invalid_arg "index"
  in
  (* A frame about to be entered at [at], above the limit: the stack is short, or the limit of depth is reached, at the
     site, the frame entered as the interpreter's is when it stops. *)
  let deep_stub at caller site =
    stub (fun s ->
        let deep = label () in
        Printf.bprintf s "  mov x0, %s\n  ble %s, %s, x0\n" (cx Ir.io_cap2) deep at;
        stop s Ir.stack_out;
        Printf.bprintf s "%s:\n" deep;
        link s at caller site;
        links s site;
        Printf.bprintf s "  mov %s, %s\n  mov %s, %d\n" (cx Ir.io_frame) at (cx Ir.io_point) fn.sites.(site);
        stop s Ir.too_deep)
  in
  let ins = function
    | Ir.Frame (r, base) -> pr "  add r%d, %s, %d\n" r (reg_of base) (if base < 0 && not nested then fn.frame + fn.hidden else 2)
    | Enter (r, base, site) ->
      let slow = deep_stub ("r" ^ string_of_int r) (reg_of base) site in
      pr "  mov x0, %s\n  bgt %s, r%d, x0\n" (cx Ir.io_lim) slow r
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
      let l = label () in
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
    | Set_elem (a, i, v, site, p) ->
      (* Against the length when owned, 0 when not: one test for both, and the cold path tells them apart. *)
      pr "  dmov y0, %s\n" (operand v);
      let err = error Ir.err_write site i (Some (Int (fst fn.arrays.(a)))) in
      let cold =
        stub (fun s ->
            Printf.bprintf s "  ubge %s, x0, %s\n" err (len a);
            spill s;
            Printf.bprintf s "  dmov d:%d(fp), y0\n  rsh x1, %s, 1\n  mov %s, x1\n  mov %s, %d\n  mov %s, %d\n" (8 * fn.frame)
              (operand i) (cx Ir.io_a) (cx Ir.io_b) (fst fn.arrays.(a)) (cx Ir.io_point) p;
            stop s Ir.copy)
      in
      (match i with
       | Ir.Reg r ->
         pr "  sub x0, r%d, 2\n  ubge %s, x0, %sw\n  lsh xa, r%d, 2\n  add xa, xa, %s\n  dmov d:-8(xa), y0\n" r cold (arr a) r (arr a)
       | Int k ->
         pr "  mov x0, %s\n  ubge %s, x0, %sw\n  dmov d:%d(%s), y0\n" (doubled (k - 1)) cold (arr a) (8 * (k - 1)) (arr a)
       | Float _ -> invalid_arg "index")
    | Wlen (r, a) -> pr "  mov r%d, %sw\n" r (arr a)
    | Call (r, k, args, site) ->
      (* The base of the callee: above the whole frame of the outermost function, 2 above a nested one. *)
      pr "  add nb, %s, %d\n" (frame_of site) (callee_of site);
      let slow = deep_stub "nb" (frame_of site) site in
      let up =
        stub (fun s ->
            link s "nb" (frame_of site) site;
            links s site;
            Printf.bprintf s "  ret %s, -1\n" zero)
      in
      pr "  mov x0, %s\n  bgt %s, nb, x0\n" (cx Ir.io_lim) slow;
      pr "  inline Q%s%d, %sg%d, r%d, fuel, cx, nb, fuel%s\n" prefix k prefix k r
        (String.concat "" (Array.to_list (Array.map (fun v -> ", " ^ operand v) args)));
      pr "  blt %s, fuel, 0\n" up
    | Try (op, r, x, y, l) ->
      let x' = in_reg Kint x in
      (match op with
       | Ir.Add -> pr "  addo r%d, %s, %s\n" r x' (operand y)
       | Sub -> pr "  subo r%d, %s, %s\n" r x' (operand y)
       | _ ->
         (match y with
          | Ir.Int n -> pr "  mulo r%d, %s, %d\n" r x' n
          | _ -> pr "  mov x1, %s\n  rsh x1, x1, 1\n  mulo r%d, %s, x1\n" (operand y) r x'));
      pr "  bo %s\n" (bl l)
    | Elem_at (r, a, i) -> pr "  lsh xa, r%d, 2\n  add xa, xa, %s\n  dmov r%d, d:-8(xa)\n" i (arr a) r
    | Set_at (a, i, v) -> pr "  dmov y0, %s\n  lsh xa, r%d, 2\n  add xa, xa, %s\n  dmov d:-8(xa), y0\n" (operand v) i (arr a)
    | Bump (r, v) -> pr "  add r%d, r%d, %s\n" r r (operand v)
    | Burn -> pr "  sub fuel, fuel, 1\n"
    | Tick (p, can_leave) ->
      let back = label () in
      let leave = can_leave && not nested in
      (* Another quantum, counted, within the limit of steps. When a full checkpoint is due, a tick of the outermost frame
         leaves there, so that fibers switch at the interpreter's step; in a nested frame, which can't, the flag asks the
         next tick that can leave to do so. *)
      let here = (not nested) && p >= 0 in
      let refill s =
        let over = label () and small = label () and due = label () and go_on = label () in
        Printf.bprintf s "  mov x0, %s\n  sub x0, x0, fuel\n  mov x1, %s\n  add x1, x1, x0\n  mov %s, x1\n"
          (cx Ir.io_quantum) (cx Ir.io_spent) (cx Ir.io_spent);
        Printf.bprintf s "  mov x2, %s\n  bgt %s, x1, x2\n  sub x2, x2, x1\n  mov x0, %s\n  ble %s, x2, x0\n  mov x2, x0\n%s:\n"
          (cx Ir.io_budget) over quantum small small;
        Printf.bprintf s "  mov x3, %s\n  bge %s, x1, x3\n  sub x3, x3, x1\n  ble %s, x2, x3\n  mov x2, x3\n  jmp %s\n"
          (cx Ir.io_until) due go_on go_on;
        Printf.bprintf s "%s:\n" due;
        if here then begin
          (* What this quantum used is in spent already. *)
          Printf.bprintf s "  mov %s, fuel\n" (cx Ir.io_quantum);
          spill s;
          Printf.bprintf s "  mov %s, %d\n" (cx Ir.io_point) p;
          stop s Ir.fuel_out
        end else Printf.bprintf s "  mov %s, 1\n" (cx Ir.io_leave);
        Printf.bprintf s "%s:\n  mov %s, x2\n  mov fuel, x2\n  jmp %s\n%s:\n  mov %s, b\n" go_on (cx Ir.io_quantum) back over
          (cx Ir.io_frame);
        stop s Ir.too_long
      in
      if leave then begin
        let out =
          stub (fun s ->
              spill s;
              Printf.bprintf s "  mov %s, %d\n" (cx Ir.io_point) p;
              stop s Ir.fuel_out)
        in
        pr "  sub fuel, fuel, 1\n  blt %s, fuel, 0\n  mov x0, %s\n  bne %s, x0, 0\n%s:\n" out (cx Ir.io_leave) out back
      end else begin
        let out = stub refill in
        pr "  sub fuel, fuel, 1\n  blt %s, fuel, 0\n%s:\n" out back
      end
  in
  let term = function
    | Ir.Jump l -> pr "  jmp %s\n" (bl l)
    | Branch (c, k, x, y, yes, no) ->
      let c, x, y = match x with Ir.Reg _ -> c, x, y | _ -> flip c, y, x in
      let x = in_reg k x in
      pr "  %sb%s %s, %s, %s\n  jmp %s\n" (if k = Kfloat then "d" else "") (cmp_name c) (bl yes) x (operand y) (bl no)
    | Return v ->
      let v = match fn.result, v with Kfloat, Int n -> Ir.Float (float_of_int n) | _ -> v in
      pr "  ret %s, fuel\n" (operand v)
    | Fuel_ge (v, yes, no) ->
      pr "  mov x0, %s\n  rsh x0, x0, 1\n  bge %s, fuel, x0\n  jmp %s\n" (operand v) (bl yes) (bl no)
    | Done ->
      spill b;
      pr "  ret 0, fuel\n"
    | Out v ->
      (match v with
       | Ir.Float _ -> pr "  mov fp, %s\n  lsh xa, b, 3\n  add fp, fp, xa\n  dmov y0, %s\n  dmov d:%d(fp), y0\n" (cx 1) (operand v) (8 * fn.frame)
       | Reg r when fn.kinds.(r) = Kfloat -> pr "  mov fp, %s\n  lsh xa, b, 3\n  add fp, fp, xa\n  dmov d:%d(fp), r%d\n" (cx 1) (8 * fn.frame) r
       | _ -> pr "  mov x0, %s\n  rsh x0, x0, 1\n  mov %s, x0\n" (operand v) (cx Ir.io_int));
      stop b Ir.returned
  in
  pr "%s%s: func %s, i64, %s\n" prefix name (ty fn.result) (args_of ~nested fn);
  pr "  local i64:nb, i64:ip, i64:fp, i64:vp, i64:xa, i64:x0, i64:x1, i64:x2, i64:x3, i64:x4, d:y0\n";
  Array.iteri (fun r k -> if not (is_param r) then pr "  local %s:r%d\n" (ty k) r) fn.kinds;
  Array.iteri (fun a (_, written) -> pr "  local i64:%s, i64:%s%s\n" (arr a) (len a) (if written then Printf.sprintf ", i64:%sw" (arr a) else "")) fn.arrays;
  let guards () =
    if Array.length fn.arrays > 0 then pr "  mov vp, %s\n  lsh xa, b, 3\n  add vp, vp, xa\n" (cx 2);
    Array.iteri
      (fun a (slot, written) ->
         pr "  mov x0, i64:%d(vp)\n  and x1, x0, 1\n  bne %s, x1, 0\n" (8 * slot) lf;
         pr "  mov x1, i64:-8(x0)\n  and x1, x1, 255\n  bne %s, x1, 3\n  mov x2, i64:0(x0)\n" lf;
         pr "  mov x1, i64:16(x2)\n  mov x3, i64:-8(x1)\n  and x3, x3, 255\n  bne %s, x3, 0\n" lf;
         pr "  mov %s, i64:0(x1)\n  mov x3, i64:0(x2)\n  rsh x3, x3, 1\n  mov x4, i64:8(x2)\n  rsh x4, x4, 1\n" (arr a);
         pr "  mul x3, x3, x4\n  lsh %s, x3, 1\n" (len a);
         if written then begin
           let l = label () in
           pr "  mov %sw, 0\n  mov x3, i64:24(x2)\n  bne %s, x3, 3\n  mov %sw, %s\n%s:\n" (arr a) l (arr a) (len a) l
         end)
      fn.arrays
  in
  let lr = Printf.sprintf "%s%s_R" prefix name in
  if nested then pr "  jmp %s\n" (bl 0)
  else begin
    pr "  bgt %s, entry, 0\n" lr;
    (* A slot of the int stack must hold an OCaml integer when the outermost frame writes it, whatever a register held. *)
    Array.iteri (fun r k -> if k = Ir.Kint && not (is_param r) then pr "  mov r%d, 0\n" r) fn.kinds;
    guards ();
    pr "  jmp %s\n%s:\n  mov ip, %s\n  lsh xa, b, 3\n  add ip, ip, xa\n  mov fp, %s\n  add fp, fp, xa\n" (bl 0) lr (cx 0) (cx 1);
    Array.iter
      (fun (v : Ir.var) ->
         match v.kind with
         | Kint -> pr "  mov r%d, i64:%d(ip)\n  sub r%d, r%d, 1\n" v.reg (8 * v.slot) v.reg v.reg
         | Kfloat -> pr "  dmov r%d, d:%d(fp)\n" v.reg (8 * v.slot))
      fn.vars;
    guards ();
    if Array.length fn.resumes > 0 then
      pr "  sub x0, entry, 1\n  switch x0, %s\n"
        (String.concat ", " (Array.to_list (Array.map bl fn.resumes)))
    else pr "  jmp %s\n" (bl 0)
  end;
  Array.iteri
    (fun l (bk : Ir.block) ->
       pr "%s:\n" (bl l);
       List.iter ins bk.ins;
       term bk.term)
    fn.blocks;
  Buffer.add_buffer b stubs;
  if not nested then begin
    pr "%s:\n" lf;
    stop b Ir.fallback
  end;
  pr "  endfunc\n"

let used = [ "sqrt"; "exp"; "log"; "sin"; "cos"; "tan"; "asin"; "acos"; "atan"; "fabs"; "pow" ]

(* The unit as one module: each function, and the single entry [e] of the first one, which the C glue calls with the
   context and which gives the status. *)
let emit (fns : Ir.func array) =
  incr units;
  let prefix = Printf.sprintf "u%d_" !units in
  let b = Buffer.create 4096 in
  let pr fmt = Printf.bprintf b fmt in
  pr "m%s: module\n  export %se\n  import %s\n" prefix prefix (String.concat ", " used);
  pr "pd1: proto d, d:a\npd2: proto d, d:a, d:b\n";
  Array.iteri
    (fun k (fn : Ir.func) ->
       pr "P%s%d: proto %s, i64, %s\n" prefix k (ty fn.result) (args_of ~nested:false fn);
       pr "Q%s%d: proto %s, i64, %s\n" prefix k (ty fn.result) (args_of ~nested:true fn))
    fns;
  (* A nested copy of each function another one calls; the first's only if one calls it. *)
  let called = Array.make (Array.length fns) false in
  Array.iter
    (fun (fn : Ir.func) ->
       Array.iter (fun (bk : Ir.block) -> List.iter (function Ir.Call (_, k, _, _) -> called.(k) <- true | _ -> ()) bk.ins) fn.blocks)
    fns;
  let nested = List.filter (fun k -> called.(k)) (List.init (Array.length fns) Fun.id) in
  if nested <> [] then pr "  forward %s\n" (String.concat ", " (List.map (fun k -> Printf.sprintf "%sg%d" prefix k) nested));
  func b ~prefix ~nested:false fns.(0);
  List.iter (fun k -> func b ~prefix ~nested:true fns.(k)) nested;
  let f0 = fns.(0) in
  pr "%se: func i64, p:cx\n  local i64:b, i64:entry, i64:fuel, i64:ip, i64:fp, i64:x0, %s:res%s\n" prefix (ty f0.result)
    (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", %s:r%d" (ty v.kind) v.reg) f0.params)));
  pr "  mov b, %s\n  mov entry, %s\n  mov fuel, %s\n  mov ip, %s\n  lsh x0, b, 3\n  add ip, ip, x0\n  mov fp, %s\n  add fp, fp, x0\n"
    (cx Ir.io_base) (cx Ir.io_entry) (cx Ir.io_fuel) (cx 0) (cx 1);
  Array.iter
    (fun (v : Ir.var) ->
       match v.kind with
       | Kint -> pr "  mov r%d, i64:%d(ip)\n  sub r%d, r%d, 1\n" v.reg (8 * v.slot) v.reg v.reg
       | Kfloat -> pr "  dmov r%d, d:%d(fp)\n" v.reg (8 * v.slot))
    f0.params;
  pr "  call P%s0, %sf0, res, fuel, cx, b, entry, fuel%s\n  blt %sX, fuel, 0\n" prefix prefix
    (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", r%d" v.reg) f0.params))) prefix;
  (match f0.result with
   | Kint -> pr "  rsh x0, res, 1\n  mov %s, x0\n" (cx Ir.io_int)
   | Kfloat -> pr "  dmov d:%d(fp), res\n" (8 * f0.frame));
  pr "  mov %s, fuel\n  ret 0\n%sX:\n  mov x0, %s\n  ret x0\n  endfunc\n  endmodule\n" (cx Ir.io_fuel) prefix (cx Ir.io_status);
  Buffer.contents b, prefix ^ "e"
