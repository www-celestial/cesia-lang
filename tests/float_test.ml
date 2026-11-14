(* The text of a float (Value.float_text, by Ryu.write) against the function it replaced, kept here only: printf "%.15g",
   else "%.16g", else "%.17g", the first that reads back, then its layout. Both must give the same bytes for every
   double. Usage: float_test.exe [N [SEED]]: N random doubles of each kind (default 50,000; the release check runs
   10^7), and every power of 2 and of 10, their neighbors, the edges of the subnormals and of the layout, +-0, nan, +-inf.
   Each kind: random bit patterns; patterns whose low mantissa bits are zero, where the ties of rounding are; subnormals;
   short decimals as people write them. *)
open Cesia

let old x =
  if Float.is_nan x then "nan"
  else if x = infinity then "inf"
  else if x = neg_infinity then "-inf"
  else begin
    let s = Printf.sprintf "%.15g" x in
    let s = if float_of_string s = x then s else Printf.sprintf "%.16g" x in
    let s = if float_of_string s = x then s else Printf.sprintf "%.17g" x in
    match String.index_opt s 'e' with
    | Some i ->
      let mant = String.sub s 0 i in
      let exp = int_of_string (let r = String.sub s (i + 1) (String.length s - i - 1) in
                               if r.[0] = '+' then String.sub r 1 (String.length r - 1) else r) in
      Printf.sprintf "%se%d" mant exp
    | None -> if String.contains s '.' then s else s ^ ".0"
  end

let checked = ref 0
let failures = ref 0
let longest = ref 0
let buffer = Bytes.make 64 '#'

let check x =
  incr checked;
  let fresh = Value.float_text x and before = old x in
  (* At an offset, the bytes around untouched. *)
  let stop = Ryu.write buffer 7 x in
  let at7 = Bytes.sub_string buffer 7 (stop - 7) in
  let clean = Bytes.get buffer 6 = '#' && Bytes.get buffer stop = '#' in
  Bytes.fill buffer 0 64 '#';
  longest := max !longest (String.length fresh);
  if fresh <> before || at7 <> fresh || not clean || String.length fresh > 24 then begin
    incr failures;
    if !failures <= 20 then
      Printf.eprintf "FAILED: %Lx (%h): new %S, at 7 %S, old %S\n" (Int64.bits_of_float x) x fresh at7 before
  end

let both x =
  check x;
  check (-.x)

let around x =
  both x;
  both (Float.succ x);
  both (Float.pred x)

let () =
  let n = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 50_000 in
  let seed = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 2026 in
  let rng = Random.State.make [| seed |] in
  List.iter check [ 0.0; -0.0; Float.nan; -.Float.nan; infinity; neg_infinity; Float.of_string "nan" ];
  for k = -1074 to 1023 do around (Float.ldexp 1.0 k) done;
  for k = -323 to 308 do around (float_of_string ("1e" ^ string_of_int k)) done;
  List.iter around
    [ Float.max_float; Float.min_float; Float.pred Float.min_float; 5e-324; 1e-5; 1e-4; 9.9999e-5; 0.001; 0.1; 0.5;
      1.0; 1.5; 2.5; 100.0; 1e14; 1e15; 1e16; 1e17; 999999999999999.0; 999999999999999.9; 9999999999999998.0;
      9007199254740992.0; 9007199254740993.0; 18014398509481984.0; 123456789012345678.0; 1e22; 1e23; 5e-310;
      2.2250738585072009e-308; 4.9406564584124654e-324; 1.7976931348623157e308; 100.0 /. 3.0; 0.1 +. 0.2 ];
  (* Every whole number from 1 to 10^5, and their tenths and hundredths. *)
  for i = 1 to 100_000 do
    let f = float_of_int i in
    check f;
    check (f /. 10.0);
    check (f /. 100.0)
  done;
  for _ = 1 to n do
    let bits = Random.State.bits64 rng in
    check (Int64.float_of_bits bits);
    let zero_low = Random.State.int rng 53 in
    check (Int64.float_of_bits (Int64.logand bits (Int64.lognot (Int64.pred (Int64.shift_left 1L zero_low)))));
    let sub = Int64.logand bits 0x800F_FFFF_FFFF_FFFFL in
    check (Int64.float_of_bits sub);
    check (Int64.float_of_bits (Int64.logand sub (Int64.lognot (Int64.pred (Int64.shift_left 1L zero_low)))));
    let digits = 1 + Random.State.int rng 17 in
    let mant = Random.State.int64 rng (Int64.of_float (10.0 ** float_of_int digits)) in
    check (float_of_string (Printf.sprintf "%Lde%d" mant (Random.State.int rng 640 - 330)))
  done;
  Printf.printf "%d doubles, %d differ; the longest text has %d bytes\n" !checked !failures !longest;
  if !failures > 0 then exit 1
