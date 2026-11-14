open Types

(* SplitMix64, written here rather than taken from Stdlib.Random: a seed gives the same numbers on every version and every
   system. The seed is the process's, from the system at the first draw unless --seed gave it; each run starts from it. *)
let seed_given = ref None
let started = ref false

(* The state: the 64 bits of the one cell of an array of floats, which native code reads and writes too, through the
   array [cell] that holds it. Only moves of its bits, never arithmetic on it as a float, so every pattern stays. *)
let store = Float.Array.make 1 0.
let cell = Arrays.of_float 1 1 store
let[@inline] get () = Int64.bits_of_float (Float.Array.get store 0)
let[@inline] put s = Float.Array.set store 0 (Int64.float_of_bits s)

let set_seed n =
  seed_given := Some n;
  put (Int64.of_int n);
  started := true

let start () =
  if not !started then begin
    let n = Random.State.bits (Random.State.make_self_init ()) in
    seed_given := Some n;
    put (Int64.of_int n);
    started := true
  end

let seed () =
  start ();
  Option.get !seed_given

(* A run starts from its seed, whatever ran before it in this process: the fuzzer and the workers of cesia test run several
   programs in one. *)
let reset () = Option.iter (fun n -> put (Int64.of_int n)) !seed_given

(* cesia test starts each test from a state of its own, made of the seed and the test's file and name, and std/cells each
   cell from the seed and its title, so that a new one changes no other's numbers; the seed of the run stays. The state
   is FNV-1a of the seed and the names, each after a zero byte. *)
let restart names =
  start ();
  let h = ref 0xcbf29ce484222325L in
  String.iter (fun c -> h := Int64.mul (Int64.logxor !h (Int64.of_int (Char.code c))) 0x100000001b3L)
    (String.concat "\000" (string_of_int (Option.get !seed_given) :: names));
  put (Int64.of_int (Int64.to_int !h))

(* One step of SplitMix64: the state moves by the golden gamma, and the number is a mix of the new state. *)
let gamma = 0x9E3779B97F4A7C15L

let[@inline] mix z =
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27)) 0x94D049BB133111EBL in
  Int64.logxor z (Int64.shift_right_logical z 31)

let next () =
  start ();
  let s = Int64.add (get ()) gamma in
  put s;
  mix s

(* A float from 0 included to 1 excluded: the 53 high bits of a number, which an OCaml integer holds exactly, so that
   the conversion is one instruction, not a call of C as Int64.to_float. *)
let[@inline] unit z = float_of_int (Int64.to_int (Int64.shift_right_logical z 11)) *. 0x1p-53

(* 62 bits, from 0 to max_int. *)
let bits () = Int64.to_int (Int64.shift_right_logical (next ()) 2)

(* From 0 to n - 1, n > 0, without the bias of a plain modulo: the draws past the last whole multiple of n are drawn again. *)
let below n =
  let rest = ((max_int mod n) + 1) mod n in
  let rec draw () =
    let r = bits () in
    if r > max_int - rest then draw () else r mod n
  in
  draw ()

let whole ctx name v =
  match v with
  | Int i -> i
  | Float x when Float.is_integer x && Float.abs x < 4e18 -> int_of_float x
  | _ -> Runtime.fail ctx Type (Messages.want_int name (Value.describe v))

let int ctx (a : t array) =
  let low = whole ctx "Int" a.(0) and high = whole ctx "Int" a.(1) in
  if low > high then Runtime.fail ctx Math (Messages.random_range low high);
  let n = high - low + 1 in
  if n <= 0 then Runtime.fail ctx Math (Messages.random_range low high);
  Int (low + below n)

(* num.Uniform(n): n draws of Float, in their order, into one row of floats, as matrix.Zeros(1, n) is; the state stays
   in a register for the loop, and goes back once. *)
let uniform ctx (a : t array) =
  let n = Native.dim ctx "Uniform" a.(0) in
  Runtime.pay ctx n;
  let d = Runtime.alloc_float ctx n 0. in
  start ();
  let s = ref (get ()) in
  for k = 0 to n - 1 do
    s := Int64.add !s gamma;
    Float.Array.set d k (unit (mix !s))
  done;
  put !s;
  Arrays.of_float 1 n d

let float = Native.nat ~ret:(fun _ -> TF) "Float" 0 0 (fun _ _ -> Float (unit (next ())))

let natives =
  [ "Int", Native.nat ~params:[| "low"; "high" |] "Int" 2 2 int;
    "Float", float;
    "Seed", Native.nat "Seed" 0 0 (fun _ _ -> Int (seed ())) ]

let num = [ "uniform", Native.nat ~ret:(fun _ -> TFA) "uniform" 1 1 uniform ]
