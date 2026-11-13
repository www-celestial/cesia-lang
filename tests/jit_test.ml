(* The JIT: MIR text made into machine code and run through the single entry. *)
open Cesia_jit

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
  let f = (Jit.load add2 [| "add2" |] 2).(1) in
  let ints = [| 0; 3; 4; 0 |] and floats = Float.Array.of_list [ 0.; 1.5; 0. ] and io = Array.make Cesia_jit.Ir.io_size 0 in
  io.(Cesia_jit.Ir.io_base) <- 1;
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
|} [| "two" |] 1).(1) in
  check "second module" (Jit.call g [||] (Float.Array.create 0) [||] (Array.make Cesia_jit.Ir.io_size 0) = 2);
  check "first still runs" (Jit.call f ints floats [||] io = 7 && ints.(3) = 7);
  print_endline "jit: hand-written MIR ok"

(* A frame of many pages: 1000 values live at once, spilled. Windows commits a thread's stack a guard page at a time, so
   such a frame must touch its pages in order; a new domain's stack is barely committed, so it runs there. *)
let () =
  let n = 1000 in
  let b = Buffer.create 65536 in
  Printf.bprintf b "m_big: module\n  export big\nbig: func i64, p:cx\n  local i64:s, i64:ints\n";
  for k = 0 to n - 1 do Printf.bprintf b "  local i64:v%d\n" k done;
  Printf.bprintf b "  mov ints, i64:0(cx)\n";
  for k = 0 to n - 1 do Printf.bprintf b "  mov v%d, i64:%d(ints)\n" k (8 * k) done;
  Printf.bprintf b "  mov s, 0\n";
  for k = n - 1 downto 0 do Printf.bprintf b "  add s, s, v%d\n" k done;
  Printf.bprintf b "  ret s\n  endfunc\n  endmodule\n";
  let f = (Jit.load (Buffer.contents b) [| "big" |] 2).(1) in
  let ints = Array.init n Fun.id in
  let run () = Jit.call f ints (Float.Array.create 0) [||] (Array.make Cesia_jit.Ir.io_size 0) in
  (* The cells of an OCaml int array hold 2k + 1. *)
  let want = (n * (n - 1)) + n in
  check "a frame of many pages" (Domain.join (Domain.spawn run) = want && run () = want);
  print_endline "jit: a frame of many pages ok"

(* A context per module: two domains make machine code at once, at both levels, and each runs; those of one freed, the
   other's still run, and a load after the frees runs too. *)
let () =
  let make k level =
    Jit.load (Printf.sprintf "m_k%d: module\n  export k%d\nk%d: func i64, p:cx\n  ret %d\n  endfunc\n  endmodule\n" k k k k)
      [| Printf.sprintf "k%d" k |] level
  in
  let run a = Jit.call a.(1) [||] (Float.Array.create 0) [||] (Array.make Cesia_jit.Ir.io_size 0) in
  let all base units = Array.for_all Fun.id (Array.mapi (fun k a -> run a = base + k) units) in
  let live = Jit.live () in
  let other = Domain.spawn (fun () -> Array.init 50 (fun k -> make (100 + k) 2)) in
  let mine = Array.init 50 (fun k -> make k 1) in
  let theirs = Domain.join other in
  check "loads at once on two domains" (all 0 mine && all 100 theirs);
  Array.iter (fun a -> Jit.free a.(0)) mine;
  check "freed, the others still run" (all 100 theirs);
  Array.iter (fun a -> Jit.free a.(0)) theirs;
  let again = make 7 2 in
  check "a load after frees" (run again = 7);
  Jit.free again.(0);
  check "none left" (Jit.live () = live);
  print_endline "jit: contexts on two domains ok"

(* A unit's level 2, made by another domain: one at a time, taken once made; dropped while it is made or once it is, its
   context is freed once, by whichever of the domain and the unit comes second. *)
let () =
  let text n =
    let b = Buffer.create 65536 in
    Printf.bprintf b "m_l2: module\n  export l2\nl2: func i64, p:cx\n  local i64:s, i64:t, i64:ints\n  mov s, 0\n";
    Printf.bprintf b "  mov ints, i64:0(cx)\n  mov t, i64:0(ints)\n";
    for k = 1 to n do Printf.bprintf b "  add s, s, t\n  xor t, t, %d\n" k done;
    Printf.bprintf b "  ret s\n  endfunc\n  endmodule\n";
    Buffer.contents b
  in
  let idle () = while Level2.busy () do Domain.cpu_relax () done in
  let live = Jit.live () in
  (match Level2.start ~wait:true (text 3) "l2" with
   | Some job ->
     (match Atomic.get job with
      | Level2.Made a ->
        (* The cell of 5 holds 11: 11 + (11 xor 1) + (11 xor 1 xor 2). *)
        let got = Jit.call a.(1) [| 5 |] (Float.Array.create 0) [||] (Array.make Cesia_jit.Ir.io_size 0) in
        check "level 2 runs" (got = 11 + 10 + 8 && Jit.live () = live + 1);
        Jit.free a.(0)
      | _ -> check "level 2 made" false)
   | None -> check "level 2 starts" false);
  (* A few thousand lines: MIR takes milliseconds at level 2, and the drop comes first. *)
  let big = text 2000 in
  (match Level2.start ~wait:false big "l2" with
   | Some job ->
     check "one at a time" (Level2.start ~wait:false big "l2" = None);
     Level2.drop job;
     idle ();
     check "dropped while made" (Atomic.get job = Level2.Abandoned && Jit.live () = live)
   | None -> check "level 2 starts" false);
  (match Level2.start ~wait:false big "l2" with
   | Some job ->
     idle ();
     check "made in the background" (match Atomic.get job with Level2.Made _ -> true | _ -> false);
     Level2.drop job;
     Level2.drop job;
     check "dropped once made, freed once" (Atomic.get job = Level2.Abandoned && Jit.live () = live)
   | None -> check "level 2 starts" false);
  (* Drops at every moment of the making: none leaves its context behind. *)
  let small = text 200 in
  for k = 0 to 39 do
    match Level2.start ~wait:false small "l2" with
    | Some job ->
      for _ = 1 to k * k * 20 do Domain.cpu_relax () done;
      Level2.drop job;
      idle ()
    | None -> check "level 2 starts" false
  done;
  check "drops leave nothing" (Jit.live () = live);
  print_endline "jit: level 2 in the background ok"

(* Versions of a real program, lowered and run natively on the interpreter's stacks. *)
open Cesia
open Cesia_jit
open Types

let program =
  {|
use std/io
use std/math
use std/matrix
use std/test
defn fib(n)
  if n < 2
    n
  else
    fib(n - 1) + fib(n - 2)
  end
end

defn mandel(w, h, maxit)
  total = 0
  for py in 0..h - 1
    y0 = 2.0 * py / h - 1.0
    for px in 0..w - 1
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
  for k in 1..n
    s = s + a[k] * b[k]
  end
  s
end

defn scale(a, n, f)
  for k in 1..n
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
  math.Div(a, b) * 1000 + math.Mod(a, b)
end

defn roots(n)
  s = 0.0
  k = 1
  while k <= n
    s = s + math.Sqrt(k) / 3.0
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

xs = matrix.Zeros(5)
ys = matrix.Zeros(5)
for k in 1..5
  xs[k] = k * 1.5
  ys[k] = 10.0 - k
end
test.Grab(fib, mandel, dot, scale, sumto, add, floors, roots, early)
io.Print(fib(15))
io.Print(mandel(40, 30, 60))
io.Print(dot(xs, ys, 5))
io.Print(scale(xs, 5, 2.0))
io.Print(sumto(1000, 0))
io.Print(add(1, 2))
io.Print(floors(-7, 2))
io.Print(roots(50))
io.Print(early(1000))
|}

let protos : (string, proto) Hashtbl.t = Hashtbl.create 8

let world, printed =
  let out = Buffer.create 64 in
  let w = Runtime.create_world { Runtime.default_options with o_sink = Buffer.add_string out; o_err = prerr_string } in
  Loader.init w;
  w.native_modules <- ("test", [ "Grab",
    Native { nname = "Grab"; perm = None; params = [||]; min_args = 0; max_args = 20; ret_ty = (fun _ -> TA); f1 = None;
              i2 = None; gives_result = false;
              run = (fun _ a ->
                  Array.iter (function Fun { proto; _ } -> Hashtbl.replace protos proto.pname proto | _ -> ()) a;
                  Missing) } ]) :: w.native_modules;
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
    (match Jit.load text [| entry |] 2 with
     | [| _; f |] -> ver, fns.(0), f
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

let float_array xs = Array { rows = 1; cols = Array.length xs; store = F (Float.Array.of_list (Array.to_list xs)); a_owned = true; a_tip = true; dims = [||] }

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
  check "the error's site is a site" (io.(Ir.io_point) >= 0 && io.(Ir.io_point) < Cesia.Vec.length world.sites);
  let ints_store = Array { rows = 1; cols = 2; store = I [| 1; 2 |]; a_owned = true; a_tip = true; dims = [||] } in
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
  (* Written, it must be owned: the interpreter copies a shared one at its first write. *)
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
  (* Last: MIR's error, in another domain, turns the JIT off for the rest of the run, on every domain. *)
  check "bad text fails"
    (Domain.join (Domain.spawn (fun () ->
         match Jit.load "m_bad: module\n  nonsense\n" [| "x" |] 2 with _ -> false | exception Failure _ -> true)));
  check "then off" (match Jit.load add2 [| "add2" |] 2 with _ -> false | exception Failure _ -> true);
  if !fails > 0 then exit 1;
  print_endline "jit lowered: ok"
