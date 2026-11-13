open Types

(* Each unit gets its own names: MIR's exported names are global. *)
let units = ref 0

(* A Cesia integer as a register holds it: 2n, which needs 64 bits. *)
let doubled n = Int64.to_string (Int64.mul 2L (Int64.of_int n))
let tagged n = Int64.to_string (Int64.add (Int64.mul 2L (Int64.of_int n)) 1L)

(* A float that MIR reads back exactly, and as a float. *)
let float_lit x =
  let s = Printf.sprintf "%.17g" x in
  if String.exists (fun c -> c = '.' || c = 'e') s then s else s ^ ".0"

let operand = function
  | Ir.Reg r -> "r" ^ string_of_int r
  | Int n -> doubled n
  | Float x -> float_lit x
  | Word n -> string_of_int n

let ty = function Ir.Kint | Kval -> "i64" | Kfloat -> "d"

(* The header of a block of OCaml 5: its size in words from bit 10, its color 0 as the young heap's, its tag, which
   native code reads alone, as the header's first byte (x86-64 and arm64 are little-endian). *)
let header words tag = string_of_int ((words lsl 10) lor tag)
let cmp_name = function Ir.Eq -> "eq" | Ne -> "ne" | Lt -> "lt" | Le -> "le" | Gt -> "gt" | Ge -> "ge"
let flip = function Ir.Lt -> Ir.Gt | Le -> Ge | Gt -> Lt | Ge -> Le | c -> c

(* A cell of the context, raw integers: the C glue copies [io] there and back. The stacks are cells 0, 1 and 2. *)
let cx k = Printf.sprintf "i64:%d(cx)" (8 * k)

(* The cell of a function's result, an integer or a double, which its caller reads at once. *)
let result_cell = function Ir.Kint | Kval -> cx Ir.cx_result | Kfloat -> Printf.sprintf "d:%d(cx)" (8 * Ir.cx_result)

(* The quantum of fuel a nested frame takes when it runs out: big, unless the limit of steps is nearer. *)
let quantum = "1099511627776"

(* The arguments every function takes before its own: the context, its base, its entry (-1 for a nested frame, 0 to start,
   1 + a resume point) and its fuel. It gives one result, as Windows x86-64 allows no more: the fuel left, its own result
   then in the context's cell [cx_result], which the caller reads after the call; or a negative fuel when it stopped: the
   status is then in the context, and each caller writes the link of its callee's frame as it goes up, for the trace.
   The fuel is the one that comes back in a register, as the next call needs it at once, and the result later. *)
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
  let params = Array.map (fun (v : Ir.var) -> v.reg) fn.params in
  let is_param r = Array.mem r params in
  (* Only the outermost frame keeps its variables in its slots, when it leaves to come back. *)
  (* MIR has two reload registers of each class for an instruction: every memory operand here has one register for its
     address, computed first, so that an instruction never needs more, whatever was spilled. *)
  (* A list, struct or map no longer owned, as [Value.share]: a block of tag 3, whose array's flag is at 24, or of tag 4
     or 8, whose own is at 16. *)
  let share b q =
    let d = label () and a = label () and rr = label () in
    Printf.bprintf b "  and x0, r%d, 1\n  bne %s, x0, 0\n  mov x1, u8:-8(r%d)\n  beq %s, x1, 3\n  beq %s, x1, 4\n  bne %s, x1, 8\n"
      q d q a rr d;
    Printf.bprintf b "%s:\n  mov i64:16(r%d), 1\n  jmp %s\n%s:\n  mov x2, i64:0(r%d)\n  mov i64:24(x2), 1\n%s:\n" rr q d a q d
  in
  (* A value goes to its slot through OCaml's write barrier, as the value stack is in the major heap; one that may be held
     elsewhere too is marked shared first. The numbers go first: MIR kept a register written after such a call in a
     stack slot for the whole function, so that `dyn`'s total went through memory at each step. *)
  let spill b =
    Printf.bprintf b "  mov ip, %s\n  lsh xa, b, 3\n  add ip, ip, xa\n  mov fp, %s\n  add fp, fp, xa\n" (cx 0) (cx 1);
    Array.iter
      (fun (v : Ir.var) ->
         match v.kind with
         | Kint -> Printf.bprintf b "  add x0, r%d, 1\n  mov i64:%d(ip), x0\n" v.reg (8 * v.slot)
         | Kfloat -> Printf.bprintf b "  dmov d:%d(fp), r%d\n" (8 * v.slot) v.reg
         | Kval -> ())
      fn.vars;
    Array.iter
      (fun (v : Ir.var) ->
         if v.kind = Kval then begin
           if Array.mem v.reg fn.lent then share b v.reg;
           Printf.bprintf b "  add x0, vp, %d\n  call pmod, caml_modify, x0, r%d\n" (8 * v.slot) v.reg
         end)
      fn.vars
  in
  let stop b status =
    Printf.bprintf b "  mov %s, fuel\n  mov %s, %d\n  ret -1\n" (cx Ir.io_fuel) (cx Ir.io_status) status
  in
  (* The frames of inlined callees around a site: their bases, the innermost first, and the links an error writes so that
     the trace holds them, as the interpreter's frames. *)
  (* An inlined frame's base is the function's own plus a constant: what is written of it is made from b, so that no
     register holds it across a call. *)
  let bases = Hashtbl.create 8 in
  Array.iter (fun (bk : Ir.block) -> List.iter (function Ir.Frame (r, base) -> Hashtbl.replace bases r base | _ -> ()) bk.ins) fn.blocks;
  let rec offset base = if base < 0 then 0 else (match Hashtbl.find bases base with -1 -> if nested then 2 else fn.frame + fn.hidden | up -> offset up + 2) in
  let frame_of site = match fn.chains.(site) with [] -> -1 | (vb, _, _) :: _ -> vb in
  let callee_of site = match fn.chains.(site) with [] -> if nested then 2 else fn.frame + fn.hidden | _ -> 2 in
  let base_in s x base = Printf.bprintf s "  add %s, b, %d\n" x (offset base) in
  let link s vb cb csite =
    Printf.bprintf s "  mov ip, %s\n" (cx 0);
    base_in s "xa" vb;
    Printf.bprintf s "  lsh xa, xa, 3\n  add ip, ip, xa\n";
    base_in s "x0" cb;
    Printf.bprintf s "  lsh x0, x0, 1\n  add x0, x0, 1\n  mov i64:0(ip), x0\n  mov i64:8(ip), %s\n" (tagged fn.sites.(csite))
  in
  let links s site = List.iter (fun (vb, cb, cs) -> link s vb cb cs) fn.chains.(site) in
  (* With a debugger, the one block where every error writes the variables back for the stop, out of the loops, as the
     ticks' below. *)
  let error_used = ref false in
  let error_block () = error_used := true; Printf.sprintf "%s%s_X" prefix name in
  (* The ends that the stubs which never come back share, each written once per function: a stub puts its own values in
     x1 to x6 and jumps to one, so MIR compiles a few lines a stub, not twenty. *)
  let ends = ref [] in
  let shared k = if not (List.mem k !ends) then ends := k :: !ends; Printf.sprintf "%s%s_%s" prefix name k in
  (* An error: the interpreter remakes its message from the operands, at the site, from this frame. *)
  let error ?(ixs = [||]) code site a bv =
    stub (fun s ->
        let raw x v =
          match v with Ir.Reg r -> Printf.bprintf s "  rsh %s, r%d, 1\n" x r | Int n -> Printf.bprintf s "  mov %s, %d\n" x n | Float _ | Word _ -> Printf.bprintf s "  mov %s, 0\n" x
        in
        Array.iteri (fun d v -> raw "x1" v; Printf.bprintf s "  mov %s, x1\n" (cx (Ir.io_ixs + d))) ixs;
        raw "x1" a;
        raw "x2" (Option.value bv ~default:(Ir.Int 0));
        links s site;
        base_in s "x5" (frame_of site);
        Printf.bprintf s "  mov x3, %d\n  mov x4, %d\n  jmp %s\n" fn.sites.(site) code (shared "E"))
  in
  (* An operand in a register, for the places MIR wants one. *)
  let in_reg k v =
    match v with
    | Ir.Reg r -> "r" ^ string_of_int r
    | _ ->
      (match k with Ir.Kint | Kval -> pr "  mov x2, %s\n" (operand v); "x2" | Kfloat -> pr "  dmov y0, %s\n" (operand v); "y0")
  in
  let arr a = Printf.sprintf "a%dd" a and len a = Printf.sprintf "a%dn" a in
  (* An array of a store of integers, whose cells are OCaml integers; and an integer operand as one, in x0. *)
  let ints a = match fn.arrays.(a) with _, _, 2, _ -> true | _ -> false in
  let tag_of v = match v with Ir.Reg q -> Printf.sprintf "add x0, r%d, 1" q | v -> Printf.sprintf "mov x0, %s" (match v with Int n -> tagged n | v -> operand v) in
  (* The size of dimension [d] of array [a], doubled. *)
  let dim a d = Printf.sprintf "a%ds%d" a d in
  let check_index ?(t = "d") a i site code =
    let slot, _, _, _ = fn.arrays.(a) in
    let raw_b = Ir.Int slot in
    match i with
    | Ir.Reg r ->
      let e = error code site i (Some raw_b) in
      pr "  sub x0, r%d, 2\n  ubge %s, x0, %s\n" r e (len a);
      Printf.sprintf "%s:-8(%s, r%d, 4)" t (arr a) r
    | Int k ->
      let e = error code site i (Some raw_b) in
      pr "  mov x0, %s\n  ubge %s, x0, %s\n" (doubled (k - 1)) e (len a);
      Printf.sprintf "%s:%d(%s)" t (8 * (k - 1)) (arr a)
    | Float _ | Word _ -> invalid_arg "index"
  in
  (* [n] words of the young heap, reserved before: the pointer moves down, the first of them in x5. *)
  let take n = pr "  mov x6, %s\n  mov x5, i64:0(x6)\n  sub x5, x5, %d\n  mov i64:0(x6), x5\n" (cx Ir.cx_young) (8 * n) in
  (* The one block that spills every variable and leaves at the point in xp: every tick that leaves goes there, so that
     MIR's allocator meets the variables' uses in one place, out of the loops. *)
  let leave_used = ref false in
  let leave_block () = leave_used := true; Printf.sprintf "%s%s_L" prefix name in
  (* A failed guard: back to the interpreter before that statement, through the block that spills and leaves. *)
  let bail_to k =
    stub (fun s ->
        let refuel = k >= Ir.refuel in
        let k = if refuel then k - Ir.refuel else k in
        let k =
          if k >= Ir.leaving then (Printf.bprintf s "  mov %s, %d\n" (cx Ir.io_code) Ir.leaving_code; k - Ir.leaving)
          else if k >= Ir.cold then (Printf.bprintf s "  mov %s, %d\n" (cx Ir.io_code) Ir.cold_code; k - Ir.cold)
          else if k < Ir.restored then k
          else begin
            let k = k - Ir.restored in
            List.iter
              (fun (r, c) -> Printf.bprintf s "  %s r%d, r%d\n" (if fn.kinds.(r) = Kfloat then "dmov" else "mov") r c)
              fn.restores.(k);
            k
          end
        in
        (* The fuel, as at the statement's start: the interpreter makes its steps again. *)
        (if refuel then
           let f, sp, q = fn.keeps.(k) in
           Printf.bprintf s "  mov fuel, r%d\n  mov %s, r%d\n  mov %s, r%d\n" f (cx Ir.io_spent) sp (cx Ir.io_quantum) q);
        Printf.bprintf s "  mov xp, %d\n  mov xs, %d\n  jmp %s\n" k Ir.bailed (leave_block ()))
  in
  (* A value whose tag is [tag], else bail: the tag in x1. *)
  let block_of v tag k =
    let b = bail_to k in
    pr "  and x0, %s, 1\n  bne %s, x0, 0\n  mov x1, u8:-8(%s)\n" v b v;
    match tag with Some t -> pr "  bne %s, x1, %d\n" b t | None -> ()
  in
  (* A frame about to be entered at [at], above the limit: the stack is short, the interpreter's frames would want a longer
     one under a limit of memory, or the limit of depth is reached; for the last two, the frame entered at the site, as the
     interpreter's is when it stops. *)
  let deep_stub at caller site =
    stub (fun s ->
        links s site;
        base_in s "x6" caller;
        Printf.bprintf s "  mov x5, %s\n  mov x4, %d\n  jmp %s\n" at fn.sites.(site) (shared "D"))
  in
  (* A call that wants a longer stack, here or deeper, bails when it can: its statement's fuel back as at its start, the
     interpreter makes the call and grows the stack. *)
  let again back = bail_to back in
  (* A frame at [at] above the limit, for a call that can bail: past the stack, or where the interpreter's frames would want
     a longer one, bail; else the limit of depth. *)
  let short at caller site back =
    let g = again back and deep = deep_stub at caller site in
    stub (fun s ->
        Printf.bprintf s "  mov x0, %s\n  bgt %s, %s, x0\n  mov x0, %s\n  bgt %s, %s, x0\n  jmp %s\n" (cx Ir.io_cap2) g at
          (cx Ir.io_mem) g at deep)
  in
  (* A new owned map ([tag] 8) or struct (4) into register [dst]: the array of values, or of doubles when all are floats,
     then its store (tag 0 F, 1 V), then the block: its keys or shape, the store, and owned. *)
  let record dst tag c vals =
    let n = Array.length vals in
    let floats = Array.for_all (function Ir.Float _ -> true | Reg q -> fn.kinds.(q) = Kfloat | _ -> false) vals in
    take (n + 7);
    pr "  mov i64:0(x5), %s\n" (header n (if floats then 254 else 0));
    Array.iteri
      (fun j v -> if floats then pr "  dmov d:%d(x5), %s\n" (8 * (j + 1)) (in_reg Kfloat v) else pr "  mov i64:%d(x5), %s\n" (8 * (j + 1)) (operand v))
      vals;
    let o = 8 * (n + 1) in
    pr "  mov i64:%d(x5), %s\n  add x6, x5, 8\n  mov i64:%d(x5), x6\n" o (header 1 (if floats then 0 else 1)) (o + 8);
    let o = o + 16 in
    pr "  mov i64:%d(x5), %s\n  mov i64:%d(x5), c%d\n  add x6, x5, %d\n  mov i64:%d(x5), x6\n  mov i64:%d(x5), 3\n  add %s, x5, %d\n"
      o (header 3 tag) (o + 8) c (o - 8) (o + 16) (o + 24) dst (o + 8)
  in
  let rec ins = function
    | Ir.Frame (r, _) -> pr "  add r%d, b, %d\n" r (offset r)
    | Enter (r, base, site, back) ->
      let at = "r" ^ string_of_int r in
      let slow = if back < 0 then deep_stub at base site else short at base site back in
      pr "  mov x0, %s\n  bgt %s, r%d, x0\n" (cx Ir.io_lim) slow r
    | Enter_or_bail (r, k) -> pr "  mov x0, %s\n  bgt %s, r%d, x0\n" (cx Ir.io_lim) (bail_to k) r
    | Ir.Move (r, v) -> pr "  %s r%d, %s\n" (if fn.kinds.(r) = Kfloat then "dmov" else "mov") r (operand v)
    | Incr r -> pr "  add r%d, r%d, 2\n" r r
    | Op (((Add | Sub) as op), r, x, y, site) when site < 0 ->
      (* Proved inside the integers: no check. *)
      pr "  %s r%d, %s, %s\n" (if op = Add then "add" else "sub") r (in_reg Kint x) (operand y)
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
    | Op (Mod, r, x, Int d, _) when d > 0 && d land (d - 1) = 0 ->
      (* By a power of two, the floor modulo is the low bits whatever the sign, and on doubled integers too: 2n land
         2(d - 1) = 2 (n land (d - 1)). No division, which costs tens of cycles. *)
      pr "  and r%d, %s, %d\n" r (in_reg Kint x) (2 * (d - 1))
    | Op (Div, r, x, Int d, _) when d > 0 && d land (d - 1) = 0 ->
      (* The floor division by 2^k is a shift right by k, which can't overflow: 2n shifted by k + 1, doubled again. *)
      let k = ref 0 in
      while 1 lsl !k < d do incr k done;
      pr "  rsh x0, %s, %d\n  lsh r%d, x0, 1\n" (in_reg Kint x) (!k + 1) r
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
    | Dim (r, a, d) -> pr "  mov r%d, %s\n" r (dim a d)
    | Elem (r, a, i, site) when fn.kinds.(r) = Kint ->
      (* A cell of a store of integers, an OCaml integer 2n + 1: the register holds 2n. *)
      pr "  mov r%d, %s\n  sub r%d, r%d, 1\n" r (check_index ~t:"i64" a i site Ir.err_read) r r
    | Elem (r, a, i, site) -> pr "  dmov r%d, %s\n" r (check_index a i site Ir.err_read)
    | Set_elem (a, i, v, site) when ints a ->
      let m = check_index ~t:"i64" a i site Ir.err_write in
      pr "  %s\n  mov %s, x0\n" (tag_of v) m
    | Set_elem (a, i, v, site) ->
      let m = check_index a i site Ir.err_write in
      pr "  dmov %s, %s\n" m (operand v)
    | Vget (r, k) -> pr "  dmov r%d, d:%d(vf)\n" r (8 * k)
    | Vset (k, v) -> pr "  dmov d:%d(vf), %s\n" (8 * k) (in_reg Kfloat v)
    | Vat (r, k, n, i, site, rows, cols) ->
      let e =
        stub (fun s ->
            (match i with Ir.Reg q -> Printf.bprintf s "  rsh x1, r%d, 1\n" q | v -> Printf.bprintf s "  mov x1, %s\n" (operand v));
            Printf.bprintf s "  mov %s, %d\n  mov x2, %d\n" (cx Ir.io_ixs) cols rows;
            links s site;
            base_in s "x5" (frame_of site);
            Printf.bprintf s "  mov x3, %d\n  mov x4, %d\n  jmp %s\n" fn.sites.(site) Ir.err_vec (shared "E"))
      in
      let q = in_reg Kint i in
      pr "  sub x0, %s, 2\n  ubge %s, x0, %s\n  dmov r%d, d:%d(vf, %s, 4)\n" q e (doubled n) r ((8 * k) - 8) q
    | Tag (r, v) ->
      let v = in_reg Kval v and word = label () and over = label () in
      pr "  and x0, %s, 1\n  bne %s, x0, 0\n  mov x1, u8:-8(%s)\n  lsh r%d, x1, 1\n  jmp %s\n" v word v r over;
      pr "%s:\n  add x1, %s, 256\n  lsh r%d, x1, 1\n%s:\n" word v r over
    | Keep (f, sp, q) -> pr "  mov r%d, fuel\n  mov r%d, %s\n  mov r%d, %s\n" f sp (cx Ir.io_spent) q (cx Ir.io_quantum)
    | Call (r, k, args, site, back) ->
      (* The base of the callee: above the whole frame of the outermost function, 2 above a nested one. *)
      let nb = offset (frame_of site) + callee_of site in
      pr "  add nb, b, %d\n" nb;
      let slow = if back < 0 then deep_stub "nb" (frame_of site) site else short "nb" (frame_of site) site back in
      let again () = again back in
      let up =
        let unwind =
          stub (fun s ->
              links s site;
              base_in s "x6" (frame_of site);
              Printf.bprintf s "  add x5, b, %d\n  mov x4, %d\n  jmp %s\n" nb fn.sites.(site) (shared "U"))
        in
        if back < 0 then unwind
        else begin
          let g = again () in
          stub (fun s ->
              Printf.bprintf s "  mov x0, %s\n  beq %s, x0, %d\n  beq %s, x0, %d\n  jmp %s\n" (cx Ir.io_status) g Ir.stack_out g
                Ir.frames_out unwind)
        end
      in
      pr "  mov x0, %s\n  bgt %s, nb, x0\n" (cx Ir.io_lim) slow;
      pr "  inline Q%s%d, %sg%d, fuel, cx, nb, fuel%s\n" prefix k prefix k
        (String.concat "" (Array.to_list (Array.map (fun v -> ", " ^ operand v) args)));
      pr "  blt %s, fuel, 0\n  %s r%d, %s\n" up (if fn.kinds.(r) = Kfloat then "dmov" else "mov") r (result_cell fn.kinds.(r))
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
    | Unbox (r, v, how, k) ->
      let v = in_reg Kval v in
      (match how with
       | Ir.Only_float -> block_of v (Some 1) k; pr "  mov x2, i64:0(%s)\n  dmov r%d, d:0(x2)\n" v r
       | Only_int -> block_of v (Some 0) k; pr "  mov x2, i64:0(%s)\n  sub r%d, x2, 1\n" v r
       | Number ->
         block_of v None k;
         let f = label () and d = label () in
         pr "  beq %s, x1, 1\n  bne %s, x1, 0\n  mov x2, i64:0(%s)\n  rsh x2, x2, 1\n  i2d r%d, x2\n  jmp %s\n" f (bail_to k) v r d;
         pr "%s:\n  mov x2, i64:0(%s)\n  dmov r%d, d:0(x2)\n%s:\n" f v r d)
    | Box (r, x) ->
      (match x with
       | Ir.Float _ | Reg _ when (match x with Reg q -> fn.kinds.(q) = Kfloat | _ -> true) ->
         let x = in_reg Kfloat x in
         take 4;
         pr "  mov i64:0(x5), %s\n  dmov d:8(x5), %s\n  mov i64:16(x5), %s\n  add x6, x5, 8\n  mov i64:24(x5), x6\n  add r%d, x5, 24\n"
           (header 1 253) x (header 1 1) r
       | _ ->
         take 2;
         (match x with Reg q -> pr "  add x6, r%d, 1\n" q | _ -> pr "  mov x6, %s\n" (match x with Int n -> tagged n | v -> operand v));
         pr "  mov i64:0(x5), %s\n  mov i64:8(x5), x6\n  add r%d, x5, 8\n" (header 1 0) r)
    | Share (Reg q) -> share b q
    | Share _ -> ()
    | Vals (r, m, c, f, k) ->
      (* The keys, then the store's kind, F (tag 0) or V (tag 1), then its array. *)
      let m = in_reg Kval m in
      block_of m (Some 8) k;
      pr "  mov x2, i64:0(%s)\n  bne %s, x2, c%d\n  mov x2, i64:8(%s)\n  mov x1, u8:-8(x2)\n" m (bail_to k) c m;
      pr "  bne %s, x1, %d\n  mov r%d, i64:0(x2)\n" (bail_to k) f r
    | Fields (r, v, sid, f, k) ->
      (* The shape's number, then the store's kind and its array. *)
      let v = in_reg Kval v in
      block_of v (Some 4) k;
      pr "  mov x2, i64:0(%s)\n  mov x2, i64:0(x2)\n  bne %s, x2, %s\n  mov x2, i64:8(%s)\n  mov x1, u8:-8(x2)\n" v (bail_to k) (tagged sid) v;
      pr "  bne %s, x1, %d\n  mov r%d, i64:0(x2)\n" (bail_to k) f r
    | Load (r, a, i, k) ->
      if k >= 0 then pr "  mov x4, i64:-8(r%d)\n  ursh x4, x4, 10\n  ble %s, x4, %d\n" a (bail_to k) i;
      if fn.kinds.(r) = Kfloat then pr "  dmov r%d, d:%d(r%d)\n" r (8 * i) a else pr "  mov r%d, i64:%d(r%d)\n" r (8 * i) a
    | Get (r, a, i, site) -> pr "  mov r%d, %s\n" r (check_index ~t:"i64" a i site Ir.err_read)
    | Put (a, i, v, site) ->
      ignore (check_index ~t:"i64" a i site Ir.err_write);
      (match i with
       | Ir.Reg q -> pr "  lsh x0, r%d, 2\n  add x0, x0, %s\n  sub x0, x0, 8\n" q (arr a)
       | Int k -> pr "  add x0, %s, %d\n" (arr a) (8 * (k - 1))
       | _ -> invalid_arg "index");
      pr "  call pmod, caml_modify, x0, %s\n" (in_reg Kval v)
    | Record (r, tag, c, vals) -> record (Printf.sprintf "r%d" r) tag c vals
    | Into (a, i, vals, c, tag, site, seen, back) ->
      (* The cell; the map or struct there, in place when it is a block of this tag, of these keys or this shape, owned,
         of an F store (tag 0); else a new one. One read and checked in this turn needs only its owned flag tested. *)
      let cell () =
        match i with
        | Ir.Reg q -> pr "  lsh x0, r%d, 2\n  add x0, x0, %s\n  sub x0, x0, 8\n" q (arr a)
        | Int k -> pr "  add x0, %s, %d\n" (arr a) (8 * (k - 1))
        | _ -> invalid_arg "index"
      in
      let fresh = label () and over = label () in
      let data =
        match seen with
        | Some (m, d) ->
          pr "  mov x2, i64:16(r%d)\n  bne %s, x2, 3\n" m fresh;
          Printf.sprintf "r%d" d
        | None ->
          ignore (check_index ~t:"i64" a i site Ir.err_write);
          cell ();
          pr "  mov x1, i64:0(x0)\n  and x2, x1, 1\n  bne %s, x2, 0\n  mov x2, u8:-8(x1)\n  bne %s, x2, %d\n" fresh fresh tag;
          pr "  mov x2, i64:0(x1)\n  bne %s, x2, c%d\n  mov x2, i64:16(x1)\n  bne %s, x2, 3\n" fresh c fresh;
          pr "  mov x2, i64:8(x1)\n  mov x3, u8:-8(x2)\n  bne %s, x3, 0\n  mov x2, i64:0(x2)\n" fresh;
          "x2"
      in
      Array.iteri (fun j v -> pr "  dmov d:%d(%s), %s\n" (8 * j) data (in_reg Kfloat v)) vals;
      if back >= 0 then
        (* Out of line, a bail that says it failed no guess. *)
        Printf.bprintf stubs "%s:\n  mov %s, %d\n  jmp %s\n" fresh (cx Ir.io_code) Ir.written (again back)
      else begin
        pr "  jmp %s\n%s:\n" over fresh;
        if seen <> None then cell ();
        record "x4" tag c vals;
        pr "  call pmod, caml_modify, x0, x4\n%s:\n" over
      end
    | Reserve (need, p) when !need > 0 ->
      let gc =
        stub (fun s ->
            Printf.bprintf s "  mov %s, %d\n  mov xp, %d\n  mov xs, %d\n  jmp %s\n" (cx Ir.io_a) !need p Ir.gc (leave_block ()))
      in
      pr "  mov x6, %s\n  mov x5, i64:0(x6)\n  sub x5, x5, %d\n  mov x6, %s\n  mov x6, i64:0(x6)\n  ublt %s, x5, x6\n"
        (cx Ir.cx_young) (8 * !need) (cx (Ir.cx_young + 1)) gc
    | Reserve _ -> ()
    | Elem_at (r, a, i, k) when fn.kinds.(r) = Kint ->
      pr "  mov r%d, i64:%d(%s, r%d, 4)\n  sub r%d, r%d, 1\n" r (8 * (k - 1)) (arr a) i r r
    | Elem_at (r, a, i, k) -> pr "  dmov r%d, d:%d(%s, r%d, 4)\n" r (8 * (k - 1)) (arr a) i
    | Offset (r, a, xs, site, write) ->
      (* Each index from 0, doubled, checked below its size; then the cell, the last index first: c = c * size + index. *)
      let slot, _, _, _ = fn.arrays.(a) in
      let e = error ~ixs:xs (if write then Ir.err_write_nd else Ir.err_read_nd) site (Int (Array.length xs)) (Some (Int slot)) in
      let from0 dst v = match v with
        | Ir.Reg q -> pr "  sub %s, r%d, 2\n" dst q
        | Int k -> pr "  mov %s, %s\n" dst (doubled (k - 1))
        | Float _ | Word _ -> invalid_arg "index"
      in
      let n = Array.length xs in
      let acc = Printf.sprintf "r%d" r in
      from0 acc xs.(n - 1);
      pr "  ubge %s, %s, %s\n" e acc (dim a (n - 1));
      for d = n - 2 downto 0 do
        from0 "x0" xs.(d);
        pr "  ubge %s, x0, %s\n  rsh x1, %s, 1\n  mul %s, %s, x1\n  add %s, %s, x0\n" e (dim a d) (dim a d) acc acc acc acc
      done;
      pr "  add %s, %s, 2\n" acc acc
    | Set_at (a, i, k, v) when ints a -> pr "  %s\n  mov i64:%d(%s, r%d, 4), x0\n" (tag_of v) (8 * (k - 1)) (arr a) i
    | Set_at (a, i, k, v) -> pr "  dmov d:%d(%s, r%d, 4), %s\n" (8 * (k - 1)) (arr a) i (operand v)
    | Bump (r, v) -> pr "  add r%d, r%d, %s\n" r r (operand v)
    | Burn -> pr "  sub fuel, fuel, 1\n"
    | Tick (p, can_leave, site) -> steps 1 p can_leave site
    | Steps (k, site) -> steps k (-1) false site
  and steps k p can_leave site =
      let back = label () in
      let leave = can_leave && not nested in
      (* Another quantum, counted, within the limit of steps. When a full checkpoint is due, a tick of the outermost frame
         leaves there, so that fibers switch at the interpreter's step; in a nested frame, which can't, the flag asks the
         next tick that can leave to do so: a fiber switch then waits until the outermost compiled call returns or reaches
         a tick that can leave (owner, 2026-11-06: « attendre la fin »). Results, errors and limits are the same; only the
         interleaving of fibers' output can differ, around native recursion. *)
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
          (* What this quantum used is in spent already. One block of the function spills and leaves, for every tick. *)
          Printf.bprintf s "  mov %s, fuel\n  mov xp, %d\n  mov xs, %d\n  jmp %s\n" (cx Ir.io_quantum) p Ir.fuel_out (leave_block ())
        end else Printf.bprintf s "  mov %s, 1\n" (cx Ir.io_leave);
        Printf.bprintf s "%s:\n  mov %s, x2\n  mov fuel, x2\n  jmp %s\n%s:\n" go_on (cx Ir.io_quantum) back over;
        (* The limit of steps, in the frame whose step this is: an inlined one's, its links written, as the interpreter's. *)
        if site >= 0 then links s site;
        base_in s "x5" (if site >= 0 then frame_of site else -1);
        Printf.bprintf s "  mov %s, x5\n" (cx Ir.io_frame);
        stop s Ir.too_long
      in
      if leave then begin
        let out = stub (fun s -> Printf.bprintf s "  mov xp, %d\n  mov xs, %d\n  jmp %s\n" p Ir.fuel_out (leave_block ())) in
        pr "  sub fuel, fuel, %d\n  blt %s, fuel, 0\n  mov x0, %s\n  bne %s, x0, 0\n%s:\n" k out (cx Ir.io_leave) out back
      end else begin
        let out = stub refill in
        pr "  sub fuel, fuel, %d\n  blt %s, fuel, 0\n%s:\n" k out back
      end
  in
  (* The steps of a statement's operations that can't leave, one after the other with nothing between them that can fail
     or show: one count of them all, at the first, which the limit of steps meets no later than the interpreter's. *)
  let rec fold = function
    | Ir.Tick (-1, false, s) :: rest ->
      let pure = function
        | Ir.Move _ | Op ((Fadd | Fsub | Fmul | Fdiv | Fpow), _, _, _, _) | Fneg _ | Float_of _ | Math _ | Vget _ | Vset _
        | Tag _ | Len _ ->
          true
        | Op ((Add | Sub), _, _, _, site) -> site < 0
        | _ -> false
      in
      let rec gather k between = function
        | Ir.Tick (-1, false, s') :: r when s' = s -> gather (k + 1) between r
        | i :: r when pure i -> gather k (i :: between) r
        | r -> k, List.rev between, r
      in
      let k, between, r = gather 1 [] rest in
      (if k = 1 then Ir.Tick (-1, false, s) else Steps (k, s)) :: between @ fold r
    | i :: rest -> i :: fold rest
    | [] -> []
  in
  (* The function's result, in its cell, just before it returns its fuel. *)
  let give v =
    let k = fn.result in
    let v = in_reg k v in
    pr "  %s %s, %s\n" (if k = Kfloat then "dmov" else "mov") (result_cell k) v
  in
  let term = function
    | Ir.Jump l -> pr "  jmp %s\n" (bl l)
    | Branch (c, k, x, y, yes, no) ->
      let c, x, y = match x with Ir.Reg _ -> c, x, y | _ -> flip c, y, x in
      let x = in_reg k x in
      pr "  %sb%s %s, %s, %s\n  jmp %s\n" (if k = Kfloat then "d" else "") (cmp_name c) (bl yes) x (operand y) (bl no)
    | Return v ->
      let v = match fn.result, v with Kfloat, Int n -> Ir.Float (float_of_int n) | _ -> v in
      give v;
      pr "  ret fuel\n"
    | Bail k -> pr "  jmp %s\n" (bail_to k)
    | Room (r, yes, no) -> pr "  mov x0, %s\n  bgt %s, r%d, x0\n  blt %s, fuel, 1\n  jmp %s\n" (cx Ir.io_lim) (bl no) r (bl no) (bl yes)
    | Fuel_ge (v, yes, no) ->
      pr "  mov x0, %s\n  rsh x0, x0, 1\n  bge %s, fuel, x0\n  jmp %s\n" (operand v) (bl yes) (bl no)
    | Is_fun (v, c, yes, no) ->
      (* A block of tag 5, Fun, whose first field, its code, is the constant's. *)
      let v = in_reg Kval v in
      pr "  and x0, %s, 1\n  bne %s, x0, 0\n  mov x1, u8:-8(%s)\n  bne %s, x1, 5\n" v (bl no) v (bl no);
      pr "  mov x2, i64:0(%s)\n  beq %s, x2, c%d\n  jmp %s\n" v (bl yes) c (bl no)
    | Done ->
      spill b;
      give (if fn.result = Kfloat then Ir.Float 0. else Int 0);
      pr "  ret fuel\n"
    | Out v when (match v with Ir.Word _ -> true | Reg r -> fn.kinds.(r) = Kval | _ -> false) ->
      (* A value: in its slot after the constants, through the write barrier. *)
      pr "  mov vp, %s\n  lsh xa, b, 3\n  add vp, vp, xa\n  add x0, vp, %d\n  call pmod, caml_modify, x0, %s\n" (cx 2)
        (8 * (fn.frame + Array.length fn.consts)) (in_reg Kval v);
      stop b Ir.returned_value
    | Out v ->
      (match v with
       | Ir.Float _ -> pr "  mov fp, %s\n  lsh xa, b, 3\n  add fp, fp, xa\n  dmov y0, %s\n  dmov d:%d(fp), y0\n" (cx 1) (operand v) (8 * fn.frame)
       | Reg r when fn.kinds.(r) = Kfloat -> pr "  mov fp, %s\n  lsh xa, b, 3\n  add fp, fp, xa\n  dmov d:%d(fp), r%d\n" (cx 1) (8 * fn.frame) r
       | _ -> pr "  mov x0, %s\n  rsh x0, x0, 1\n  mov %s, x0\n" (operand v) (cx Ir.io_int));
      stop b Ir.returned
  in
  pr "%s%s: func i64, %s\n" prefix name (args_of ~nested fn);
  pr "  local i64:nb, i64:ip, i64:fp, i64:vp, i64:vf, i64:xa, i64:xp, i64:xs, i64:x0, i64:x1, i64:x2, i64:x3, i64:x4, i64:x5, i64:x6, d:y0\n";
  Array.iteri (fun j _ -> pr "  local i64:c%d\n" j) fn.consts;
  Array.iteri (fun r k -> if not (is_param r) then pr "  local %s:r%d\n" (ty k) r) fn.kinds;
  Array.iteri
    (fun a (_, _, _, nd) ->
       pr "  local i64:%s, i64:%s\n" (arr a) (len a);
       for d = 0 to nd - 1 do pr "  local i64:%s\n" (dim a d) done)
    fn.arrays;

  let guards () =
    Array.iteri
      (fun a (slot, written, store, nd) ->
         pr "  mov x0, i64:%d(vp)\n  and x1, x0, 1\n  bne %s, x1, 0\n" (8 * slot) lf;
         pr "  mov x1, u8:-8(x0)\n  bne %s, x1, 3\n  mov x2, i64:0(x0)\n" lf;
         pr "  mov x1, i64:16(x2)\n  mov x3, u8:-8(x1)\n  bne %s, x3, %d\n" lf store;
         if written then pr "  mov x3, i64:24(x2)\n  bne %s, x3, 3\n" lf;
         pr "  mov %s, i64:0(x1)\n  mov x3, i64:0(x2)\n  rsh x3, x3, 1\n  mov x4, i64:8(x2)\n  rsh x4, x4, 1\n" (arr a);
         pr "  mul x3, x3, x4\n  lsh %s, x3, 1\n" (len a);
         (* Indexes one per dimension: as many dimensions, whose sizes, doubled, come from rows and cols for two and from
            dims past them, an empty array for two. *)
         if nd > 0 then begin
           pr "  mov x1, i64:40(x2)\n  mov x3, i64:-8(x1)\n  ursh x3, x3, 10\n  bne %s, x3, %d\n" lf (if nd = 2 then 0 else nd);
           for d = 0 to nd - 1 do
             if nd = 2 then pr "  mov %s, i64:%d(x2)\n" (dim a d) (8 * d) else pr "  mov %s, i64:%d(x1)\n" (dim a d) (8 * d);
             pr "  sub %s, %s, 1\n" (dim a d) (dim a d)
           done
         end)
      fn.arrays
  in
  let lr = Printf.sprintf "%s%s_R" prefix name and lg = Printf.sprintf "%s%s_G" prefix name in
  if nested then pr "  jmp %s\n" (bl 0)
  else begin
    (* The value stack at the frame, then, at the start or at a resume point, the variables; then once for both the
       constants and the checks of the arrays: nothing moves them while native code runs. *)
    if Array.length fn.arrays > 0 || Array.length fn.consts > 0 || Array.exists (fun (v : Ir.var) -> v.kind = Kval) fn.vars
    then pr "  mov vp, %s\n  lsh xa, b, 3\n  add vp, vp, xa\n" (cx 2);
    (* The area of small arrays of floats, the last hidden slots of the float stack, where nothing moves while the run
       lasts. *)
    if fn.vslots > 0 then
      pr "  mov vf, %s\n  lsh xa, b, 3\n  add vf, vf, xa\n  add vf, vf, %d\n" (cx 1) (8 * (fn.frame + fn.hidden - fn.vslots));
    pr "  bgt %s, entry, 0\n" lr;
    (* A slot of the int stack must hold an OCaml integer when the outermost frame writes it, whatever a register held. *)
    Array.iter (fun (v : Ir.var) -> if v.kind = Kint && not (is_param v.reg) then pr "  mov r%d, 0\n" v.reg) fn.vars;
    Array.iter (fun (v : Ir.var) -> if v.kind = Kval then pr "  mov r%d, 1\n" v.reg) fn.vars;
    pr "  jmp %s\n%s:\n  mov ip, %s\n  lsh xa, b, 3\n  add ip, ip, xa\n  mov fp, %s\n  add fp, fp, xa\n" lg lr (cx 0) (cx 1);
    Array.iter
      (fun (v : Ir.var) ->
         match v.kind with
         | Kint -> pr "  mov r%d, i64:%d(ip)\n  sub r%d, r%d, 1\n" v.reg (8 * v.slot) v.reg v.reg
         | Kfloat -> pr "  dmov r%d, d:%d(fp)\n" v.reg (8 * v.slot)
         | Kval -> pr "  mov r%d, i64:%d(vp)\n" v.reg (8 * v.slot))
      fn.vars;
    pr "%s:\n" lg;
    Array.iteri (fun j _ -> pr "  mov x0, i64:%d(vp)\n  mov c%d, i64:0(x0)\n" (8 * (fn.frame + j)) j) fn.consts;
    guards ();
    pr "  switch entry, %s\n" (String.concat ", " (bl 0 :: Array.to_list (Array.map bl fn.resumes)))
  end;
  Array.iteri
    (fun l (bk : Ir.block) ->
       pr "%s:\n" (bl l);
       List.iter ins (fold bk.ins);
       term bk.term)
    fn.blocks;
  Buffer.add_buffer b stubs;
  (* The link of the frame at x5 to its caller's at x6, from the site x4. *)
  let link_x () =
    pr "  mov ip, %s\n  lsh xa, x5, 3\n  add ip, ip, xa\n  lsh x0, x6, 1\n  add x0, x0, 1\n  mov i64:0(ip), x0\n" (cx 0);
    pr "  lsh x0, x4, 1\n  add x0, x0, 1\n  mov i64:8(ip), x0\n"
  in
  List.iter
    (fun k ->
       pr "%s%s_%s:\n" prefix name k;
       match k with
       | "E" ->
         (* An error: its operands x1 and x2, its site x3, its code x4, its frame x5. *)
         pr "  mov %s, x1\n  mov %s, x2\n  mov %s, x3\n  mov %s, x4\n  mov %s, x5\n" (cx Ir.io_a) (cx Ir.io_b) (cx Ir.io_point)
           (cx Ir.io_code) (cx Ir.io_frame);
         if fn.spills && not nested then pr "  jmp %s\n" (error_block ()) else stop b Ir.error
       | "D" ->
         (* A frame at x5 past the limit, entered from x6 at the site x4: the stack is short, the interpreter's frames would
            want a longer one under a limit of memory (first, as its call grows the stack before anything else), or the
            limit of depth is reached; for the last two, the frame entered, as the interpreter's is when it stops. *)
         let frames = label () and deep = label () in
         pr "  mov x0, %s\n  ble %s, x5, x0\n" (cx Ir.io_cap2) frames;
         stop b Ir.stack_out;
         pr "%s:\n  mov x1, %d\n  mov x0, %s\n  ble %s, x5, x0\n  mov x1, %d\n%s:\n" frames Ir.too_deep (cx Ir.io_mem) deep
           Ir.frames_out deep;
         link_x ();
         pr "  mov %s, x5\n  mov %s, x4\n  mov %s, fuel\n  mov %s, x1\n  ret -1\n" (cx Ir.io_frame) (cx Ir.io_point) (cx Ir.io_fuel)
           (cx Ir.io_status)
       | _ ->
         (* A call at x5 that stopped, on its way up: its frame's link; with a debugger, an error deeper writes this frame's
            variables back too, as one here does. *)
         link_x ();
         if fn.spills && not nested then begin
           let l = label () in
           pr "  mov x0, %s\n  bne %s, x0, %d\n" (cx Ir.io_status) l Ir.error;
           spill b;
           pr "%s:\n" l
         end;
         pr "  ret -1\n")
    (List.rev !ends);
  if !leave_used then begin
    pr "%s:\n" (leave_block ());
    spill b;
    pr "  mov %s, xp\n  mov %s, fuel\n  mov %s, xs\n  ret -1\n" (cx Ir.io_point) (cx Ir.io_fuel) (cx Ir.io_status)
  end;
  if !error_used then begin
    pr "%s:\n" (error_block ());
    spill b;
    stop b Ir.error
  end;
  if not nested then begin
    pr "%s:\n" lf;
    stop b Ir.fallback
  end;
  pr "  endfunc\n"

let used = [ "sqrt"; "exp"; "log"; "sin"; "cos"; "tan"; "asin"; "acos"; "atan"; "fabs"; "pow"; "caml_modify" ]

(* The unit as one module: each function, and the single entry [e] of the first one, which the C glue calls with the
   context and which gives the status. *)
let emit (fns : Ir.func array) =
  incr units;
  let prefix = Printf.sprintf "u%d_" !units in
  let b = Buffer.create 4096 in
  let pr fmt = Printf.bprintf b fmt in
  pr "m%s: module\n  export %se\n  import %s\n" prefix prefix (String.concat ", " used);
  pr "pd1: proto d, d:a\npd2: proto d, d:a, d:b\npmod: proto i64:a, i64:b\n";
  Array.iteri
    (fun k (fn : Ir.func) ->
       pr "P%s%d: proto i64, %s\n" prefix k (args_of ~nested:false fn);
       pr "Q%s%d: proto i64, %s\n" prefix k (args_of ~nested:true fn))
    fns;
  (* A nested copy of each function another one calls; the first's only if one calls it. *)
  let called = Array.make (Array.length fns) false in
  Array.iter
    (fun (fn : Ir.func) ->
       Array.iter (fun (bk : Ir.block) -> List.iter (function Ir.Call (_, k, _, _, _) -> called.(k) <- true | _ -> ()) bk.ins) fn.blocks)
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
       | Kfloat -> pr "  dmov r%d, d:%d(fp)\n" v.reg (8 * v.slot)
       | Kval -> invalid_arg "Mirtext: a value as a parameter")
    f0.params;
  pr "  call P%s0, %sf0, fuel, cx, b, entry, fuel%s\n  blt %sX, fuel, 0\n  %s res, %s\n" prefix prefix
    (String.concat "" (Array.to_list (Array.map (fun (v : Ir.var) -> Printf.sprintf ", r%d" v.reg) f0.params))) prefix
    (if f0.result = Kfloat then "dmov" else "mov") (result_cell f0.result);
  (match f0.result with
   | Kint | Kval -> pr "  rsh x0, res, 1\n  mov %s, x0\n" (cx Ir.io_int)
   | Kfloat -> pr "  dmov d:%d(fp), res\n" (8 * f0.frame));
  pr "  mov %s, fuel\n  ret 0\n%sX:\n  mov x0, %s\n  ret x0\n  endfunc\n  endmodule\n" (cx Ir.io_fuel) prefix (cx Ir.io_status);
  Buffer.contents b, prefix ^ "e"
