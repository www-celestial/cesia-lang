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
add2:   func i64, p:ints, p:floats, p:vals, p:io
        local i64:b, i64:x, i64:y, d:f
        mov b, i64:0(io)
        rsh b, b, 1
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
  let ints = [| 0; 3; 4; 0 |] and floats = Float.Array.of_list [ 0.; 1.5; 0. ] and io = [| 1 |] in
  let status = Jit.call f ints floats [||] io in
  check "status" (status = 7);
  check "int sum" (ints.(3) = 7);
  check "float double" (Float.Array.get floats 2 = 3.0);
  check "others untouched" (ints.(0) = 0 && ints.(1) = 3 && Float.Array.get floats 0 = 0.);
  (* A second module links beside the first. *)
  let g = (Jit.load {|
m_two:  module
        export two
two:    func i64, p:ints, p:floats, p:vals, p:io
        ret 2
        endfunc
        endmodule
|} [| "two" |]).(0) in
  check "second module" (Jit.call g [||] (Float.Array.create 0) [||] [| 0 |] = 2);
  check "first still runs" (Jit.call f ints floats [||] io = 7 && ints.(3) = 7);
  (* MIR's error comes back as Failure, and turns the JIT off for the run. *)
  check "bad text fails" (match Jit.load "m_bad: module\n  nonsense\n" [| "x" |] with _ -> false | exception Failure _ -> true);
  check "then off" (match Jit.load add2 [| "add2" |] with _ -> false | exception Failure _ -> true);
  if !fails > 0 then exit 1;
  print_endline "jit: ok"
