(* The JIT: MIR text made into machine code and run through the single entry. *)
open Cesia_sys

let fails = ref 0

let check name ok =
  if not ok then begin
    incr fails;
    Printf.printf "FAILED: %s\n" name
  end

(* Reads two ints at the base, writes their sum after them; doubles a float. Ints are tagged: 2n + 1. *)
let add2 =
  {|
m_add2: module
        export add2
add2:   func i64, p:cx
        local i64:b, i64:x, i64:y, d:f, i64:ints, i64:floats
        mov ints, i64:0(cx)
        mov floats, i64:8(cx)
        mov b, i64:24(cx)
        mov x, i64:0(ints, b, 8)
        mov y, i64:8(ints, b, 8)
        rsh x, x, 1
        rsh y, y, 1
        add x, x, y
        lsh x, x, 1
        add x, x, 1
        mov i64:16(ints, b, 8), x
        dmov f, d:0(floats, b, 8)
        dadd f, f, f
        dmov d:8(floats, b, 8), f
        ret 7
        endfunc
        endmodule
|}

let () =
  let f = (Jit.load add2 [| "add2" |]).(0) in
  let ints = [| 0; 3; 4; 0 |] and floats = Float.Array.of_list [ 0.; 1.5; 0. ] and io = Array.make Cesia.Ir.io_size 0 in
  io.(Cesia.Ir.io_base) <- 1;
  let status = Jit.call f ints floats [||] io in
  check "status" (status = 7);
  check "int sum" (ints.(3) = 7);
  check "float double" (Float.Array.get floats 2 = 3.0);
  check "others untouched" (ints.(0) = 0 && ints.(1) = 3 && Float.Array.get floats 0 = 0.);
  (* A second module links beside the first. *)
  let g = (Jit.load {|
m_two:  module
        export two
two:    func i64, p:cx
        ret 2
        endfunc
        endmodule
|} [| "two" |]).(0) in
  check "second module" (Jit.call g [||] (Float.Array.create 0) [||] (Array.make Cesia.Ir.io_size 0) = 2);
  check "first still runs" (Jit.call f ints floats [||] io = 7 && ints.(3) = 7);
  print_endline "jit: hand-written MIR ok"

(* Versions of a real program, lowered and run natively on the interpreter's stacks. *)
open Cesia
open Types

let program =
  {|
defn fib(n)
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

defn mandel(w, h, maxit)
  total = 0
  for py in 0:h - 1
    y0 = 2.0 * py / h - 1.0
    for px in 0:w - 1
      x0 = 3.0 * px / w - 2.0
      x = 0.0
      y = 0.0
      iter = 0
      x2 = 0.0
      y2 = 0.0
      while x2 + y2 < 4.0 and iter < maxit
        y = 2.0 * x * y + y0
        x = x2 - y2 + x0
        x2 = x * x
        y2 = y * y
        iter = iter + 1
      end
      total = total + iter
    end
  end
  total
end

defn dot(a, b, n)
  s = 0.0
  for k in 1:n
    s = s + a[k] * b[k]
  end
  s
end

defn scale(a, n, f)
  for k in 1:n
    a[k] = a[k] * f
  end
  n
end

defn sumto(n, acc)
  if n == 0
    acc
  else
    sumto(n - 1, acc + n)
  end
end

defn add(a, b)
  a + b
end

defn floors(a, b)
  Div(a, b) * 1000 + Mod(a, b)
end

defn roots(n)
  s = 0.0
  k = 1
  while k <= n
    s = s + Sqrt(k) / 3.0
    k = k + 1
  end
  s
end

defn early(n)
  k = 0
  while true
    if k * k > n
      break
    end
    k = k + 1
  end
  k
end

xs = Zeros(5)
ys = Zeros(5)
for k in 1:5
  xs[k] = k * 1.5
  ys[k] = 10.0 - k
end
Grab(fib, mandel, dot, scale, sumto, add, floors, roots, early)
Print(fib(15))
Print(mandel(40, 30, 60))
Print(dot(xs, ys, 5))
Print(scale(xs, 5, 2.0))
Print(sumto(1000, 0))
Print(add(1, 2))
Print(floors(-7, 2))
Print(roots(50))
Print(early(1000))
|}

let protos : (string, proto) Hashtbl.t = Hashtbl.create 8

let world, printed =
  let out = Buffer.create 64 in
  let w = Runtime.create_world { Runtime.default_options with o_sink = Buffer.add_string out; o_err = prerr_string } in
  Loader.init w;
  Native.register w "Grab"
    (Native { nname = "Grab"; perm = None; params = [||]; min_args = 0; max_args = 20; ret_ty = (fun _ -> TA); f1 = None;
              i2 = None;
              run = (fun _ a ->
                  Array.iter (function Fun { proto; _ } -> Hashtbl.replace protos proto.pname proto | _ -> ()) a;
                  Missing) });
  let path = Filename.temp_file "jit" ".ce" in
  Out_channel.with_open_bin path (fun oc -> output_string oc program);
  let code = Loader.run w path [] in
  Sys.remove path;
  check "program runs" (code = 0);
  w, Array.of_list (String.split_on_char '\n' (String.trim (Buffer.contents out)))

let version name sg =
  let p = Hashtbl.find protos name in
  List.find (fun (v : version) -> v.sg = sg) p.versions

(* The unit of a version as machine code, and a run of it: its status, and io and the stacks after. *)
let native name sg =
  let ver = version name sg in
  match Lower.unit world ver with
  | None -> failwith ("not lowered: " ^ name)
  | Some fns ->
    let text, entry = Mirtext.emit fns in
    (* JIT_TEST_SHOW=fib prints the MIR of a unit. *)
    if Sys.getenv_opt "JIT_TEST_SHOW" = Some name then print_string text;
    (match Jit.load text [| entry |] with
     | [| f |] -> ver, fns.(0), f
     | _ -> assert false
     | exception Failure m -> prerr_endline text; failwith (name ^ ": " ^ m))

let b = 10

let stacks () = Array.make 4096 0, Float.Array.make 4096 0., Array.make 4096 Missing

let run ?(fuel = max_int / 4) ?(until = max_int / 4) ?(entry = 0) (ver : version) f (ints, floats, vals) args =
  Array.iteri
    (fun k a ->
       let slot = ver.pk.(k) / 4 in
       match ver.pk.(k) land 3, a with
       | 1, Int n -> ints.(b + slot) <- n
       | 2, Float x -> Float.Array.set floats (b + slot) x
       | 0, v -> vals.(b + slot) <- v
       | _ -> assert false)
    args;
  let io = Array.make Ir.io_size 0 in
  io.(Ir.io_base) <- b;
  io.(Ir.io_entry) <- entry;
  io.(Ir.io_fuel) <- fuel;
  io.(Ir.io_quantum) <- fuel;
  io.(Ir.io_cap2) <- Array.length ints - 2;
  io.(Ir.io_depth) <- max_int / 4;
  io.(Ir.io_lim) <- Array.length ints - 2;
  io.(Ir.io_budget) <- max_int / 4;
  io.(Ir.io_until) <- until;
  let status = Jit.call f ints floats vals io in
  status, io

let float_array xs = Array { rows = 1; cols = Array.length xs; store = F (Float.Array.of_list (Array.to_list xs)); a_owned = true; a_tip = true }

let () =
  check "Array is the block of tag 3, F of tag 0, as the native code reads them"
    (Obj.tag (Obj.repr (float_array [| 1. |])) = 3
     && (match float_array [| 1. |] with Array a -> Obj.tag (Obj.repr a.store) = 0 | _ -> false));
  let line k = printed.(k) in
  (* fib: recursion, ints *)
  let ver, _, f = native "fib" [| TI |] in
  let st, io = run ver f (stacks ()) [| Int 25 |] in
  check "fib status" (st = Ir.ok);
  check "fib 25" (io.(Ir.io_int) = 75025);
  let st, io = run ver f (stacks ()) [| Int 15 |] in
  check "fib 15 as the interpreter" (st = 0 && string_of_int io.(Ir.io_int) = line 0);
  (* mandel: floats, nested loops, while with and *)
  let ver, _, f = native "mandel" [| TI; TI; TI |] in
  let st, io = run ver f (stacks ()) [| Int 40; Int 30; Int 60 |] in
  check "mandel as the interpreter" (st = 0 && string_of_int io.(Ir.io_int) = line 1);
  let st, io = run ver f (stacks ()) [| Int 600; Int 400; Int 200 |] in
  check "mandel of the benchmark" (st = 0 && io.(Ir.io_int) = 13428156);
  (* Fuel out: leave, come back at the resume point, same result. *)
  (* A full checkpoint due every 500 steps: the ticks outside inner loops leave, and the run comes back. *)
  let resumed ?(fuel = 1000) ver f args =
    let s = stacks () in
    let st, io = run ~fuel ~until:500 ver f s args in
    let st = ref st and io = ref io and trips = ref 0 in
    while !st = Ir.fuel_out do
      incr trips;
      let s2, io2 = run ~fuel ~until:500 ~entry:(!io.(Ir.io_point) + 1) ver f s [||] in
      st := s2;
      io := io2
    done;
    !st, !io, !trips, s
  in
  let st, io, trips, _ = resumed ver f [| Int 40; Int 30; Int 60 |] in
  check "mandel through fuel" (st = 0 && string_of_int io.(Ir.io_int) = line 1 && trips > 5);
  (* dot: float arrays read *)
  let xs = float_array [| 1.5; 3.0; 4.5; 6.0; 7.5 |] and ys = float_array [| 9.; 8.; 7.; 6.; 5. |] in
  let ver, fn, f = native "dot" [| TFA; TFA; TI |] in
  let (_, floats, _) as s = stacks () in
  let st, _ = run ver f s [| xs; ys; Int 5 |] in
  let r = Float.Array.get floats (b + fn.frame) in
  check "dot as the interpreter" (st = 0 && Value.float_text r = line 2);
  let st, io = run ver f (stacks ()) [| xs; ys; Int 6 |] in
  check "dot outside the array" (st = Ir.error && io.(Ir.io_code) = Ir.err_read && io.(Ir.io_a) = 6 && io.(Ir.io_b) = ver.map.(0));
  check "the error's site is a site" (io.(Ir.io_point) >= 0 && io.(Ir.io_point) < Dynarray.length world.sites);
  let ints_store = Array { rows = 1; cols = 2; store = I [| 1; 2 |]; a_owned = true; a_tip = true } in
  let st, _ = run ver f (stacks ()) [| ints_store; ys; Int 2 |] in
  check "an array of ints falls back" (st = Ir.fallback);
  (* scale: float arrays written, owned only *)
  let ver, _, f = native "scale" [| TFA; TI; TF |] in
  let a = float_array [| 1.; 2.; 3. |] in
  let st, io = run ver f (stacks ()) [| a; Int 3; Float 2.5 |] in
  check "scale writes" (st = 0 && io.(Ir.io_int) = 3
                        && (match a with Array { store = F d; _ } -> Float.Array.to_list d = [ 2.5; 5.; 7.5 ] | _ -> false));
  let shared = float_array [| 1.; 2. |] in
  (match shared with Array r -> r.a_owned <- false | _ -> ());
  let st, _ = run ver f (stacks ()) [| shared; Int 2; Float 2.0 |] in
  check "a shared array falls back, untouched"
    (st = Ir.fallback && (match shared with Array { store = F d; _ } -> Float.Array.to_list d = [ 1.; 2. ] | _ -> false));
  (* sumto: a self tail call loops *)
  let ver, _, f = native "sumto" [| TI; TI |] in
  let st, io = run ver f (stacks ()) [| Int 1000; Int 0 |] in
  check "sumto as the interpreter" (st = 0 && string_of_int io.(Ir.io_int) = line 4);
  let st, io, _, _ = resumed ver f [| Int 1_000_000; Int 0 |] in
  check "sumto deep, through fuel" (st = 0 && io.(Ir.io_int) = 500000500000);
  (* add: overflow *)
  let ver, _, f = native "add" [| TI; TI |] in
  let st, io = run ver f (stacks ()) [| Int 1; Int 2 |] in
  check "add" (st = 0 && string_of_int io.(Ir.io_int) = line 5);
  let st, io = run ver f (stacks ()) [| Int max_int; Int 1 |] in
  check "add overflows at 63 bits" (st = Ir.error && io.(Ir.io_code) = Ir.err_add && io.(Ir.io_a) = max_int && io.(Ir.io_b) = 1);
  let st, io = run ver f (stacks ()) [| Int min_int; Int (-1) |] in
  check "add overflows below" (st = Ir.error && io.(Ir.io_code) = Ir.err_add);
  let st, io = run ver f (stacks ()) [| Int (max_int - 1); Int 1 |] in
  check "add up to max_int" (st = 0 && io.(Ir.io_int) = max_int);
  (* floors: Div and Mod as Cesia's *)
  let ver, _, f = native "floors" [| TI; TI |] in
  let st, io = run ver f (stacks ()) [| Int (-7); Int 2 |] in
  check "floors as the interpreter" (st = 0 && string_of_int io.(Ir.io_int) = line 6);
  let cases = [ 7, 2; -7, -2; 7, -2; 0, 5; -1, 3; 9, 3 ] in
  List.iter
    (fun (x, y) ->
       let st, io = run ver f (stacks ()) [| Int x; Int y |] in
       let want = (((if x mod y <> 0 && x < 0 <> (y < 0) then (x / y) - 1 else x / y)) * 1000)
                  + (let r = x mod y in if r <> 0 && r < 0 <> (y < 0) then r + y else r) in
       check (Printf.sprintf "floors %d %d" x y) (st = 0 && io.(Ir.io_int) = want))
    cases;
  let st, io = run ver f (stacks ()) [| Int 1; Int 0 |] in
  check "Div by zero" (st = Ir.error && io.(Ir.io_code) = Ir.err_div);
  let st, io = run ver f (stacks ()) [| Int min_int; Int (-1) |] in
  check "Div overflow" (st = Ir.error && io.(Ir.io_code) = Ir.err_div && io.(Ir.io_a) = min_int);
  (* roots: while, Sqrt from libm, float division *)
  let ver, fn, f = native "roots" [| TI |] in
  let (_, floats, _) as s = stacks () in
  let st, _ = run ver f s [| Int 50 |] in
  check "roots as the interpreter, to the bit" (st = 0 && Value.float_text (Float.Array.get floats (b + fn.frame)) = line 7);
  (* early: while true and break *)
  let ver, _, f = native "early" [| TI |] in
  let st, io = run ver f (stacks ()) [| Int 1000 |] in
  check "break" (st = 0 && string_of_int io.(Ir.io_int) = line 8);
  (* Last: MIR's error turns the JIT off for the rest of the run. *)
  check "bad text fails" (match Jit.load "m_bad: module\n  nonsense\n" [| "x" |] with _ -> false | exception Failure _ -> true);
  check "then off" (match Jit.load add2 [| "add2" |] with _ -> false | exception Failure _ -> true);
  if !fails > 0 then exit 1;
  print_endline "jit lowered: ok"
