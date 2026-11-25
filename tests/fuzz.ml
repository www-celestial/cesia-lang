(* The fuzzer: random bytes and mutated valid programs, with strict limits. Only Cesia errors are allowed. The two
   paths, typed and --no-spec, must also give the same result; with CESIA_JIT=always, the typed path runs natively all it
   can, and with --jit the programs are of the shapes the JIT compiles, whose loops get hot on the typed path. The
   entries of the cache of loaded packages are fuzzed too: random bytes, real ones changed, and real ones changed in
   their records with their checksums made again. Usage:
   fuzz.exe --seconds N --seed S [--jit], from the
   repository root. Failures go to _build/fuzz_fail/. *)
open Cesia

exception Timeout

let fail_dir = "_build/fuzz_fail"
let current = Filename.concat fail_dir "current.ce"
let max_saved = 40
let trial_alarm = 10

let limits =
  { Runtime.default_limits with steps = 1_000_000; memory_words = 64 * 1024 * 1024 / 8; max_depth = 1000 }

type outcome = { code : int; out : string; err : string }

let run ?(after = ignore) ~no_spec path =
  let out = Buffer.create 256 and err = Buffer.create 256 in
  let sink b s = if Buffer.length b < 1 lsl 20 then Buffer.add_string b s in
  let options =
    { Runtime.default_options with
      o_limits = limits;
      o_no_spec = no_spec;
      o_sink = sink out;
      o_err = sink err }
  in
  let w = Runtime.create_world options in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register ~max_sleep:0.001 w in
  let code = Loader.run_file ~strict:true w path [] in
  after w;
  { code; out = Buffer.contents out; err = Buffer.contents err }

let contains text s =
  let n = String.length s and m = String.length text in
  let rec go i = i + m <= n && (String.sub s i m = text || go (i + 1)) in
  go 0

let hit_limit o = contains "Limit \"" o.err

let write path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let finished = ref 0

(* None if all is well, else what is wrong. *)
let attempt src =
  write current src;
  match
    ignore (Unix.alarm trial_alarm);
    let a = run ~no_spec:false current in
    let b = run ~no_spec:true current in
    ignore (Unix.alarm 0);
    a, b
  with
  | exception e ->
    ignore (Unix.alarm 0);
    Some ("exception: " ^ Printexc.to_string e)
  | a, b ->
    if a.code = 0 then incr finished;
    if hit_limit a || hit_limit b || a = b then None
    else
      Some
        (Printf.sprintf "paths differ\n--- typed (%d)\n%s%s\n--- no-spec (%d)\n%s%s" a.code a.out a.err b.code
           b.out b.err)

(* Makes a test file runnable: otherwise its isFoo functions would never be called. *)
let test_calls src =
  let call line =
    let name_of start =
      match String.index_from_opt line start '(' with
      | Some i when String.sub line i (min 2 (String.length line - i)) = "()" ->
        Some (String.sub line start (i - start))
      | _ -> None
    in
    let is_test at =
      String.length line > at + 2 && String.sub line at 2 = "is" && line.[at + 2] >= 'A' && line.[at + 2] <= 'Z'
    in
    let found =
      if is_test 0 then name_of 0
      else if String.starts_with ~prefix:"defn " line && is_test 5 then name_of 5
      else None
    in
    Option.map (fun n -> Printf.sprintf "io.Print(fiber.Wait(fiber.Spawn(%s)))\n" n) found
  in
  String.concat "" (List.filter_map call (String.split_on_char '\n' src))

let std_calls =
  "io.Print(list.Map(x -> x + 1, [1, 2]))\n\
   io.Print(list.Filter(x -> x > 1, [1, 2, 3]))\n\
   io.Print(list.Reduce((a, x) -> a + x, 0, [1, 2, 3]))\n\
   io.Print(list.Scan((a, x) -> a + x, 0, [1, 2, 3]))\n\
   io.Print(list.Range(1, 10, step = 3))\n\
   io.Print(list.Group(x -> math.Mod(x, 2), [1, 2, 3, 4]))\n\
   io.Print(list.Top(2, [5, 1, 9, 3]))\n\
   io.Print(list.Frequencies([1, 2.0, 1, \"a\"]))\n\
   io.Print(list.Top(2, [{V: 1}, {V: 3}, {V: 2}], by = x -> x.V))\n\
   io.Print(list.Group(x -> x, [\"a\", \"b\", \"a\"]))\n\
   fuzzCube = matrix.Reshape([2, 3, 4], 1..24)\n\
   io.Print(fuzzCube[2, 3, 4], fuzzCube[1, 2, 3] + fuzzCube[7], value.Size(fuzzCube))\n\
   io.Print(list.Sum(fuzzCube, dim = 3), list.Mean(fuzzCube * 1.5, dim = 1))\n\
   fuzzField = matrix.Zeros(3, 3, 3)\n\
   for k in 1..3\n  for j in 1..3\n    for i in 1..3\n      fuzzField[i, j, k] = i * j - k * 0.5\n    end\n  end\nend\n\
   io.Print(fuzzField + 1.0, fuzzField * fuzzField > 1.0, list.Fill(\"a\", 1, 2, 2))\n"

(* The uses of the packages that the calls above name, at the end of a program, unless it has them. *)
let with_uses ?(extra = []) src =
  let has text =
    let n = String.length src and m = String.length text in
    let rec go i = i + m <= n && (String.sub src i m = text || go (i + 1)) in
    go 0
  in
  src ^ String.concat "" (List.map (fun p -> if has ("use std/" ^ p) then "" else "\nuse std/" ^ p) ([ "io"; "fiber"; "list"; "math" ] @ extra)) ^ "\n"

let kp_files dir =
  if not (Sys.file_exists dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort compare
    |> List.filter (fun f -> Filename.check_suffix f ".ce")
    |> List.map (Filename.concat dir)

let corpus () =
  let read f = In_channel.with_open_bin f In_channel.input_all in
  let programs = kp_files "tests/lang" @ kp_files "tests/net" @ kp_files "tests/c" in
  let tests = List.map (fun f -> let s = read f in with_uses (s ^ "\n" ^ test_calls s)) programs in
  let std = List.map (fun f -> with_uses ~extra:[ "matrix"; "value" ] (read f ^ "\n" ^ std_calls)) (kp_files "src/std") in
  Array.of_list (tests @ std)

(* Splits into words, spaces and signs: gluing the pieces gives back the original text. *)
let tokens s =
  let out = ref [] and n = String.length s and i = ref 0 in
  let is_word c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_' || c = '.'
  in
  let is_space c = c = ' ' || c = '\n' || c = '\t' in
  while !i < n do
    let start = !i and c = s.[!i] in
    let same = if is_word c then is_word else if is_space c then is_space else fun _ -> false in
    incr i;
    while !i < n && same s.[!i] do incr i done;
    out := String.sub s start (!i - start) :: !out
  done;
  Array.of_list (List.rev !out)

let is_number t = t <> "" && t.[0] >= '0' && t.[0] <= '9'
let hostile = [| "0"; "-1"; "4611686018427387903"; "nan"; "1e19"; "1.5"; "(1.0 / 0.0)"; "fiber.Spawn"; "fiber.Wait"; "missing" |]

let pick st a = a.(Random.State.int st (Array.length a))

let mutate st src =
  let t = ref (tokens src) in
  let count () = Array.length !t in
  let at () = Random.State.int st (count ()) in
  for _ = 0 to Random.State.int st 4 do
    if count () > 1 then
      match Random.State.int st 4 with
      | 0 ->
        let k = at () in
        t := Array.append (Array.sub !t 0 k) (Array.sub !t (k + 1) (count () - k - 1))
      | 1 ->
        let k = at () in
        t := Array.concat [ Array.sub !t 0 k; [| !t.(k) |]; Array.sub !t k (count () - k) ]
      | 2 ->
        let a = at () and b = at () in
        let x = !t.(a) in
        !t.(a) <- !t.(b);
        !t.(b) <- x
      | _ ->
        let numbers = List.filter (fun k -> is_number !t.(k)) (List.init (count ()) Fun.id) in
        if numbers <> [] then begin
          let k = List.nth numbers (Random.State.int st (List.length numbers)) in
          !t.(k) <- pick st hostile
        end
  done;
  String.concat "" (Array.to_list !t)

let random_bytes st = String.init (Random.State.int st 400) (fun _ -> Char.chr (Random.State.int st 256))

let generate st corpus =
  if Random.State.bool st || Array.length corpus = 0 then random_bytes st else mutate st (pick st corpus)

(* A program of the shapes the JIT makes machine code of, at random: loops long enough to get hot, over lists of
   integers read and written by index, small arrays of floats made by literals, calls through a value and operations
   cell by cell, branches the JIT leaves to the interpreter, and now and then a value of another kind or an index out of
   its array late in the loop. The typed path runs them natively, the --no-spec path in the interpreter: both must say
   the same. *)
(* The loops of a sparse product in CSC: an outer loop over columns, its indexes j + k checked before it, an inner loop
   over a range read from a list of integers, whose rows index y. The last call may break a list (a row outside y, a
   float, a short colptr, a huge or the smallest integer, a write into the rows while the loops run). *)
let csc st =
  let b = Buffer.create 2048 in
  let p fmt = Printf.bprintf b fmt in
  let int a z = a + Random.State.int st (z - a + 1) in
  let coin () = Random.State.bool st in
  let n = int 40 160 and per = int 1 4 and dx = int 0 2 in
  let calls = 1 + (120_000 / (n * (per + 2))) in
  p "use std/io\nuse std/list\nuse std/math\nuse std/matrix\n\n";
  p "defn fuzzMul(colptr, rowidx, vals, x, n, at, v)\n  y = matrix.Zeros(n)\n  rowidx[1] = rowidx[1]\n  s = 0.0\n";
  p "  for j in 1..n\n    xj = x[j + %d]\n" dx;
  p "    for q in colptr[j]..colptr[j + 1] - 1\n      i = rowidx[q]\n      y[i] = y[i] + vals[q] * xj\n";
  p "      if q == at\n        rowidx[q + 1] = v\n      end\n    end\n";
  if coin () then p "    s = s + x[j + %d] * %d.5\n" (int 0 dx) (int 0 3);
  if coin () then p "    y[j] = y[j] + s * 0.001\n";
  p "  end\n  io.Print(list.Sum(y), y[1], y[n], s)\n  y\nend\n\n";
  p "n = %d\ncolptr = list.Fill(0, n + 1)\nrowidx = list.Fill(0, %d * n + 1)\np = 1\n" n per;
  p "for j in 1..n\n  colptr[j] = p\n  for e in 1..math.Mod(j * %d, %d)\n" (int 1 7) (per + 1);
  p "    rowidx[p] = math.Mod(j * %d + e * %d, n) + 1\n    p += 1\n  end\nend\ncolptr[n + 1] = p\n" (int 1 97) (int 1 13);
  p "rowidx = list.Take(p - 1, rowidx)\nvals = matrix.Zeros(p - 1) + 0.25\nfor q in 1..p - 1\n  vals[q] = q * 0.5\nend\n";
  p "x = matrix.Zeros(n + %d) + 1.5\nfor r in 1..%d\n  y = fuzzMul(colptr, rowidx, vals, x, n, 0, 0)\nend\n" dx calls;
  let r = "math.Mod(" ^ string_of_int (int 1 1000) ^ ", p - 1) + 1" in
  (match int 0 9 with
   | 0 -> p "rowidx[%s] = %s\n" r (pick st [| "n + 1"; "0"; "-1"; "2.0"; "2.5" |])
   | 1 -> p "colptr = list.Take(n, colptr)\n"
   | 2 -> p "colptr[%d] = %s\n" (int 2 n) (pick st [| "4611686018427387903"; "-4611686018427387903 - 1"; "p + 5"; "0" |])
   | 3 -> p "y = fuzzMul(colptr, rowidx, vals, x, n, %s, %s)\n" r (pick st [| "1"; "n"; "n + 1"; "0.5"; "3.0" |])
   | 4 -> p "x = matrix.Zeros(n)\n"
   | _ -> ());
  p "y = fuzzMul(colptr, rowidx, vals, x, n, 0, 0)\n";
  Buffer.contents b

(* A small system of equations stepped in a loop, with a histogram of a list of integers. *)
let odes st =
  let b = Buffer.create 2048 in
  let p fmt = Printf.bprintf b fmt in
  let int a z = a + Random.State.int st (z - a + 1) in
  let n = int 2 4 and m = int 3 9 and turns = int 21000 26000 in
  let coin () = Random.State.bool st in
  let flt () = Printf.sprintf "%d.%d" (int 0 3) (int 0 99) in
  let cell () = Printf.sprintf "y[%d]" (int 1 n) in
  (* A scalar of the cells of y, t and constants, kept small. *)
  let rec scalar d =
    match if d = 0 then int 0 2 else int 0 6 with
    | 0 -> cell ()
    | 1 -> flt ()
    | 2 -> "t"
    | 3 -> Printf.sprintf "(%s + %s)" (scalar (d - 1)) (scalar (d - 1))
    | 4 -> Printf.sprintf "(%s - %s)" (scalar (d - 1)) (scalar (d - 1))
    | 5 -> Printf.sprintf "(%s * %s)" (scalar (d - 1)) (scalar (d - 1))
    | _ -> Printf.sprintf "%s / (1.0 + math.Abs(%s))" (scalar (d - 1)) (scalar (d - 1))
  in
  (* An array of n cells, of y and k, cell by cell. *)
  let rec vec d =
    match if d = 0 then int 0 1 else int 0 7 with
    | 0 -> "y"
    | 1 -> "k"
    | 2 -> Printf.sprintf "(%s + %s)" (vec (d - 1)) (vec (d - 1))
    | 3 -> Printf.sprintf "(%s - %s * %s)" (vec (d - 1)) (flt ()) (vec (d - 1))
    | 4 -> Printf.sprintf "(%s * %s)" (scalar 1) (vec (d - 1))
    | 5 -> Printf.sprintf "math.Abs(%s)" (vec (d - 1))
    | 6 -> Printf.sprintf "list.%s(%s, %s)" (if coin () then "Max" else "Min") (vec (d - 1)) (vec (d - 1))
    | _ -> Printf.sprintf "(%s / (1.0 + math.Abs(%s)))" (vec (d - 1)) (vec (d - 1))
  in
  let literal () = "[" ^ String.concat ", " (List.init n (fun _ -> scalar 2)) ^ "]" in
  p "use std/io\nuse std/list\nuse std/math\nuse std/value\n\n";
  p "fuzzF(t, y) = %s\n" (literal ());
  p "fuzzG(t, y) = if t > %d.5 %s else %s end\n\n" (int 1 turns) (literal ()) (literal ());
  p "defn fuzzRun(f, idx, turns)\n  y = [%s]\n  k = y * 0.5\n  acc = 0.0\n  cnt = 0\n  hist = list.Fill(0, %d)\n" (String.concat ", " (List.init n (fun _ -> flt ()))) m;
  p "  for i in 1..turns\n    t = i * 0.0001\n    k = f(t, y)\n";
  p "    y = %s * 0.25 + y * 0.5\n" (vec 2);
  p "    j = idx[math.Mod(i, %d) + 1]\n    hist[j] = hist[j] + 1\n" m;
  p "    acc = acc + list.Sum(%s) * 0.001 + y[math.Mod(j, %d) + 1]\n" (vec 1) n;
  p "    if acc > %d.0\n      acc = acc / %d.0\n      cnt += 1\n" (int 1 50) (int 2 9);
  if coin () then p "      if cnt == %d\n        io.Print(\"turn $i: $y\")\n      end\n" (int 1 40);
  p "    end\n";
  if coin () then p "    if i == %d\n      k = list.Max(k, y) - [%s]\n    end\n" (int 1 turns) (String.concat ", " (List.init n (fun _ -> flt ())));
  if Random.State.int st 4 = 0 then p "    if i == %d\n      acc = acc + idx[%d]\n    end\n" (int 15000 turns) (m + 1);
  if Random.State.int st 4 = 0 then p "    if i == %d\n      y = y + [%s]\n    end\n" (int 15000 turns) (String.concat "; " (List.init n (fun _ -> "1.0")));
  p "  end\n  io.Print(y, acc, cnt, hist)\nend\n\n";
  p "idx = list.Fill(1, %d)\nfor i in 1..%d\n  idx[i] = math.Mod(i * %d, %d) + 1\nend\n" m m (int 1 7) m;
  p "fuzzRun(%s, idx, %d)\n" (if coin () then "fuzzF" else "fuzzG") turns;
  Buffer.contents b

(* Calls through a value with no argument, f(), in a loop: closures of nothing that give integers or floats, random
   draws among them, inlined or called, more of them than a call remembers now and then, and late in the loop one that
   gives a text, NaN or an integer past 63 bits; and a branch the JIT leaves to the interpreter (a text built) taken at
   every turn, or rarely. Both paths draw the same numbers: each run starts from the seed. *)
let thunks st =
  let b = Buffer.create 2048 in
  let p fmt = Printf.bprintf b fmt in
  let int a z = a + Random.State.int st (z - a + 1) in
  let coin () = Random.State.bool st in
  let turns = int 21000 30000 and nf = int 1 6 in
  let body k =
    match int 0 7 with
    | 0 -> Printf.sprintf "%d" (int (-9) 99)
    | 1 -> Printf.sprintf "%d.%d" (int 0 9) (int 0 99)
    | 2 -> Printf.sprintf "fuzzK * %d.5" (int 0 3)
    | 3 -> Printf.sprintf "fuzzN + %d" k
    | 4 -> Printf.sprintf "math.Sqrt(%d.25)" (int 0 50)
    | 5 -> "random.Float()"
    | 6 -> Printf.sprintf "random.Float() * %d.5 - fuzzK" (int 0 9)
    | _ -> "fuzzLoop()"
  in
  p "use std/io\nuse std/math\nuse std/random\nuse std/value\n\nfuzzK = %d.%d\nfuzzN = %d\n" (int 0 9) (int 0 9) (int 0 1000);
  p "defn fuzzLoop()\n  s = 0.0\n  for j in 1..%d\n    s = s + j * 0.5\n  end\n  s\nend\n" (int 1 4);
  for k = 1 to nf do p "fuzzF%d() = %s\n" k (body k) done;
  p "fuzzText() = \"t\"\nfuzzNan() = 0.0 / 0.0\nfuzzBig() = 4611686018427387903\n\n";
  p "defn fuzzRun(ops, last, turns, every)\n  acc = %s\n  t = \"\"\n  for i in 1..turns\n" (if coin () then "0" else "0.0");
  p "    f = if i < turns - %d ops[math.Mod(i * %d, value.Len(ops)) + 1] else last end\n" (int 0 20) (int 1 7);
  p "    acc = %s\n" (pick st [| "acc + f()"; "acc * 0.5 + f()"; "f() - acc * 0.25"; "acc + f() * 2" |]);
  p "    if math.Mod(i, every) == 0\n      t = \"k$i\"\n    end\n";
  p "    if acc > %d.0\n      acc = acc / 2\n    end\n  end\n  io.Print(acc, value.Len(t))\nend\n\n" (int 100 100000);
  let ops = String.concat ", " (List.init nf (fun k -> Printf.sprintf "fuzzF%d" (k + 1))) in
  let last = pick st [| "fuzzF1"; "fuzzF1"; "fuzzText"; "fuzzNan"; "fuzzBig"; "() -> 1.5" |] in
  p "fuzzRun([%s], %s, %d, %d)\n" ops last turns (pick st [| 1; 1; 2; 1000; turns + 1 |]);
  Buffer.contents b

(* A loop at the top of a file over variables of the file that its functions read, which machine code keeps in registers
   and writes back to their cells: integers and a float, the loop's own variable one of them or not, a function inlined
   that reads one, a loop inside, a branch left to the interpreter now and then, and late in the loop an index out of
   its list, a float given to an integer or an overflow. *)
let tops st =
  let b = Buffer.create 1024 in
  let p fmt = Printf.bprintf b fmt in
  let int a z = a + Random.State.int st (z - a + 1) in
  let coin () = Random.State.bool st in
  let v = if coin () then "fuzzI" else "i" and turns = int 21000 30000 in
  p "use std/io\nuse std/math\n\nfuzzA = %d\nfuzzB = %d.5\nfuzzC = 0\nfuzzI = 0\nfuzzT = \"\"\n" (int 0 9) (int 0 9);
  p "defn fuzzShow()\n  \"$fuzzA $fuzzB $fuzzC $fuzzI $fuzzT\"\nend\nfuzzGet(x) = x + fuzzA\n\n";
  p "for %s in 1..%d\n  fuzzA = math.Mod(fuzzA * %d + %s, 1000003)\n" v turns (int 1 9) v;
  if coin () then p "  fuzzB = fuzzB * 0.5 + %d.25\n" (int 0 9);
  if coin () then p "  fuzzC = math.Mod(fuzzGet(fuzzC), 99991)\n";
  if coin () then p "  for j in 1..%d\n    fuzzC = fuzzC + j\n  end\n" (int 1 4);
  if coin () then p "  if math.Mod(%s, %d) == 0\n    fuzzT = \"t$fuzzA\"\n  end\n" v (pick st [| 1; 2; 7; 1000 |]);
  (match int 0 5 with
   | 0 -> p "  if %s == %d\n    fuzzA = fuzzA + [1, 2][3]\n  end\n" v (int 15000 turns)
   | 1 -> p "  if %s == %d\n    fuzzA = 2.5\n  end\n" v (int 15000 turns)
   | 2 -> p "  if %s == %d\n    fuzzC = 4611686018427387903 + fuzzC\n  end\n" v (int 15000 turns)
   | _ -> ());
  p "end\nio.Print(fuzzShow())\n";
  Buffer.contents b

(* Calls of functions with defaults in a hot loop, which machine code makes directly: arguments left out, given, or
   named in any order; defaults of literals, of a parameter before, and of a division that fails late or never; a
   callee with a loop, called and not inlined; and a self tail call that gives the argument its first frame took by
   default, a call into another version. *)
let defaults st =
  let b = Buffer.create 1024 in
  let p fmt = Printf.bprintf b fmt in
  let int a z = a + Random.State.int st (z - a + 1) in
  let turns = int 21000 30000 in
  let lit () = pick st [| string_of_int (int 0 9); Printf.sprintf "%d.5" (int 0 4) |] in
  let plus = pick st [| lit (); "x * 2"; "by + 1"; Printf.sprintf "math.Div(12, x - %d)" (int 15000 (turns + 9000)) |] in
  p "use std/io\nuse std/math\n\ndefn fuzzA(x, by = %s, plus = %s)\n  x * by + plus\nend\n\n" (lit ()) plus;
  p "defn fuzzLoop(n, from = %d, by = %s)\n  t = 0\n  for k in from..n\n    t = t + by * k\n  end\n  t\nend\n\n" (int 0 3) (lit ());
  p "defn fuzzCount(n, acc = %d)\n  if n <= 0\n    return acc\n  end\n  fuzzCount(n - 1, acc + %s)\nend\n\n" (int 0 5)
    (pick st [| "1"; "n"; "0.5" |]);
  let call () =
    match int 0 7 with
    | 0 -> "fuzzA(i)"
    | 1 -> Printf.sprintf "fuzzA(i, %s)" (lit ())
    | 2 -> Printf.sprintf "fuzzA(i, plus = %s)" (lit ())
    | 3 -> Printf.sprintf "fuzzA(plus = %s, x = i)" (lit ())
    | 4 -> Printf.sprintf "fuzzA(by = math.Mod(i, %d), x = i)" (int 1 9)
    | 5 -> Printf.sprintf "fuzzLoop(math.Mod(i, %d)%s)" (int 1 9) (pick st [| ""; ", by = 2"; ", 1, 3"; ", by = 0.5, from = 2" |])
    | _ -> Printf.sprintf "fuzzCount(math.Mod(i, %d))" (int 1 30)
  in
  p "defn fuzzRun(turns)\n  acc = 0.0\n  for i in 1..turns\n";
  for _ = 1 to int 1 3 do p "    acc = acc + %s\n" (call ()) done;
  p "  end\n  acc\nend\nio.Print(fuzzRun(%d))\n" turns;
  Buffer.contents b

(* Versions as a whole that give values, called natively from a hot loop and from one the interpreter keeps: a test that
   loops and gives a Bool, a search that gives an integer or missing, a parameter given back (two names of one map, then
   a write through one), a recursion of Bools, trees of maps made by a recursion, now and then past the young heap; and
   late in the loop a condition that is no Bool, an overflow, or a value of another kind. *)
let values st =
  let b = Buffer.create 2048 in
  let p fmt = Printf.bprintf b fmt in
  let int a z = a + Random.State.int st (z - a + 1) in
  let coin () = Random.State.bool st in
  let turns = int 21000 30000 in
  let late = int 15000 (turns + 5000) in
  p "use std/io\nuse std/math\nuse std/value\n\n";
  p "defn fuzzP(n)\n  if n < %d\n    return false\n  end\n  d = 2\n  while d * d <= n\n" (int 1 3);
  p "    if math.Mod(n, d) == 0\n      return false\n    end\n    d = d + 1\n  end\n  true\nend\n\n";
  p "defn fuzzFind(n, most)\n  for k in 1..most\n    if k * k > n\n      return %s\n    end\n  end\n  missing\nend\n\n"
    (pick st [| "k"; "k * 0.5"; "k + n" |]);
  p "fuzzSame(p) = p\n\n";
  p "defn fuzzOdd(n)\n  if n == 0\n    return false\n  end\n  not fuzzOdd(n - 1)\nend\n\n";
  p "defn fuzzTree(n)\n  if n == 0\n    return {L: missing, R: missing}\n  end\n  {L: fuzzTree(n - 1), R: fuzzTree(n - 1)}\nend\n\n";
  p "defn fuzzCond(n)\n  v = if n == %d %s else n > %d end\n  if v\n    return 1\n  end\n  0\nend\n\n" late
    (pick st [| "7"; "missing"; "\"t\""; "true" |]) (int 0 9);
  p "defn fuzzRun(turns)\n  c = 0\n  total = 0\n  p = missing\n  q = missing\n  t = missing\n  for i in 1..turns\n";
  if coin () then p "    if fuzzP(math.Mod(i, %d))\n      c = c + 1\n    end\n" (int 50 3000);
  if coin () then p "    x = fuzzFind(math.Mod(i, %d), %d)\n    if x != missing\n      total = total + x\n    end\n" (int 10 5000) (int 1 80);
  if coin () then p "    p = {X: i}\n    q = fuzzSame(p)\n";
  if coin () then p "    if fuzzOdd(math.Mod(i, %d))\n      c = c + 2\n    end\n" (int 1 40);
  if coin () then p "    c = c + fuzzCond(i)\n";
  if coin () then p "    if math.Mod(i, %d) == 0\n      t = fuzzTree(%d)\n    end\n" (int 1 500) (int 1 7);
  (match int 0 5 with
   | 0 -> p "    if i == %d\n      t = fuzzTree(%d)\n    end\n" late (int 16 18)
   | 1 -> p "    if i == %d\n      total = total + fuzzFind(4611686018427387903, 3)\n    end\n" late
   | 2 -> p "    if i == %d\n      total = total + fuzzSame(\"t\")\n    end\n" late
   | _ -> ());
  p "  end\n  if value.IsDict(q)\n    q.X = 5\n  end\n  io.Print(c, total, value.IsMissing(t))\n  if value.IsDict(p)\n    io.Print(p.X)\n  end\nend\n\n";
  (* From a loop the interpreter keeps, as it makes a text: the versions' own entries. *)
  p "defn fuzzSlow(turns)\n  c = 0\n  s = \"\"\n  for i in 1..turns\n    if fuzzP(math.Mod(i, 97))\n      c = c + 1\n    end\n";
  p "    t = fuzzTree(%d)\n    s = \"$i\"\n  end\n  io.Print(c, s)\nend\n\n" (int 1 6);
  p "fuzzRun(%d)\n" turns;
  if coin () then p "fuzzSlow(%d)\n" (int 1000 3000);
  Buffer.contents b

let shaped st =
  match Random.State.int st 7 with
  | 0 -> csc st | 1 -> thunks st | 2 -> tops st | 3 -> defaults st | 4 -> values st | _ -> odes st

let toml_sample = "[project]\nname = \"x\"\nnative = ['a', \"b\"]\n\n[tasks.a] # c\nrun = [\n  \"sh\",\n]\nwatch = true\n"
let toml_bytes = "\"'[]=.,#\\\n\r\t"

let rec toml_files dir =
  if not (Sys.file_exists dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort compare
    |> List.concat_map (fun f ->
           let path = Filename.concat dir f in
           if Sys.is_directory path then toml_files path else if f = "cesia.toml" then [ path ] else [])

let toml_corpus () =
  let read f = In_channel.with_open_bin f In_channel.input_all in
  Array.of_list (toml_sample :: List.map read (toml_files "tests/project"))

let mutate_toml st src =
  let text = ref src in
  for _ = 0 to Random.State.int st 8 do
    let s = !text in
    let n = String.length s in
    let k = Random.State.int st (n + 1) in
    let c = String.make 1 toml_bytes.[Random.State.int st (String.length toml_bytes)] in
    text :=
      (match Random.State.int st 3 with
       | 0 -> String.sub s 0 k ^ c ^ String.sub s k (n - k)
       | 1 when k < n -> String.sub s 0 k ^ String.sub s (k + 1) (n - k - 1)
       | _ when k < n -> String.sub s 0 k ^ c ^ String.sub s (k + 1) (n - k - 1)
       | _ -> s)
  done;
  !text

let generate_toml st corpus = if Random.State.bool st then random_bytes st else mutate_toml st (pick st corpus)
let toml_accepted = ref 0

(* The reader takes hostile bytes: any input gives a result. *)
let attempt_toml src =
  match
    ignore (Unix.alarm trial_alarm);
    Toml.parse src
  with
  | exception e ->
    ignore (Unix.alarm 0);
    Some ("toml exception: " ^ Printexc.to_string e)
  | result ->
    ignore (Unix.alarm 0);
    if Result.is_ok result then incr toml_accepted;
    None

(* Entries of the cache of loaded packages, in memory: those of some packages of std/, made at the start by a program
   that names one function of each, which loads its Cesia code. *)
let mem : (string, string) Hashtbl.t = Hashtbl.create 16
let part k off len = String.sub (Option.value (Hashtbl.find_opt mem k) ~default:"") off len
let store = { Cache.build = "fuzz"; map = (fun k -> Option.map (fun s -> String.length s, part k) (Hashtbl.find_opt mem k)); write = Hashtbl.replace mem }
let entry_file = Filename.concat fail_dir "entry.ce"
let tail s = if String.length s < 24 then String.length s else 24 + Int64.to_int (String.get_int64_le s 16)

(* Where each record of an entry is named: a byte 1, the record's place in the tail and its length, then its checksum,
   in the head or in a record. A place that only looks so has a checksum that doesn't match: none is found by chance. *)
let records s =
  let t = tail s and n = String.length s in
  let rec uint p acc shift = if p >= n || shift > 56 then None else let c = Char.code s.[p] in
    if c < 128 then Some (acc lor (c lsl shift), p + 1) else uint (p + 1) (acc lor ((c land 127) lsl shift)) (shift + 7) in
  let found = ref [] in
  for p = 24 to n - 1 do
    if s.[p] = '\001' then
      match uint (p + 1) 0 0 with
      | Some (at, q) ->
        (match uint q 0 0 with
         | Some (len, q) when at >= 0 && len > 0 && q + 8 <= n && at <= n - t - len
                              && Int64.equal (String.get_int64_le s q) (Cache.checksum s (t + at) len) ->
           found := (at, len, q) :: !found
         | _ -> ())
      | None -> ()
  done;
  List.sort compare !found

(* An entry whose records changed, sealed again: the checksum of each record, inner ones first, as they come in the
   tail, then that of the head. *)
let reseal s refs =
  let b = Bytes.of_string s and t = tail s in
  List.iter (fun (at, len, q) -> Bytes.set_int64_le b q (Cache.checksum (Bytes.to_string b) (t + at) len)) refs;
  Bytes.set_int64_le b 8 (Cache.checksum (Bytes.to_string b) 24 (t - 24));
  Bytes.to_string b

let first_function src =
  List.find_map
    (fun line ->
       let line = if String.starts_with ~prefix:"defn " line then String.sub line 5 (String.length line - 5) else line in
       let n = String.length line in
       let rec stop i = if i < n && (match line.[i] with 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true | _ -> false) then stop (i + 1) else i in
       let i = stop 0 in
       if i > 0 && i < n && line.[i] = '(' && (match line.[0] with 'A' .. 'Z' -> true | _ -> false) then Some (String.sub line 0 i) else None)
    (String.split_on_char '\n' src)

(* Each package: its program, what it gives without a cache, and its entries with where their records are named. *)
let entries_corpus () =
  List.filter_map
    (fun name ->
       match Option.bind (Embedded.file name) first_function with
       | None -> None
       | Some f ->
         let src = Printf.sprintf "use std/%s\n\nfuzzEntry = %s.%s\n" name name f in
         write entry_file src;
         let plain = run ~no_spec:false entry_file in
         Hashtbl.reset mem;
         Cache.store := Some store;
         ignore (run ~no_spec:false entry_file);
         Cache.save ();
         Cache.store := None;
         let entries = Hashtbl.fold (fun k v acc -> (k, v, records v) :: acc) mem [] in
         if plain.code = 0 && entries <> [] then Some (src, plain, entries) else None)
    [ "plot"; "stats"; "frame"; "markdown"; "special"; "syntax"; "algo"; "heap" ]

let mutate_entry st s =
  let n = String.length s in
  let b = Bytes.of_string s in
  let at () = Random.State.int st (max n 1) in
  match Random.State.int st 4 with
  | 0 -> random_bytes st
  | 1 -> String.sub s 0 (at ())
  | 2 -> let k = at () in String.sub s 0 k ^ String.make 1 (Char.chr (Random.State.int st 256)) ^ String.sub s k (n - k)
  | _ ->
    for _ = 0 to Random.State.int st 8 do
      let k = at () in
      if k < n then Bytes.set b k (Char.chr (Char.code s.[k] lxor (1 lsl Random.State.int st 8)))
    done;
    Bytes.to_string b

(* Bytes of the tail changed in place, flipped or set at random. *)
let mutate_tail st s =
  let b = Bytes.of_string s and t = tail s and n = String.length s in
  if n > t then
    for _ = 0 to Random.State.int st 16 do
      let k = t + Random.State.int st (n - t) in
      Bytes.set b k (if Random.State.bool st then Char.chr (Random.State.int st 256) else Char.chr (Char.code s.[k] lxor 1))
    done;
  Bytes.to_string b

let rec read_all (f : Ast.func) =
  Array.iter (fun (p : Ast.param) -> Option.iter read_expr p.default) f.params;
  Array.iter read_expr (Lazy.force f.body)
and read_expr (e : Ast.expr) = match e.e with Lambda g | Fn_def (_, g) -> read_all g | _ -> Resolve.children read_expr e

(* One entry of a package, changed: random bytes, changed or cut, are not used; changed in its records and sealed again,
   each body read after the run still reads or is taken from its source. The program gives what it gives without a
   cache, and nothing raises but a Cesia error. *)
let entry_trials = ref 0 and sealed_trials = ref 0

let attempt_entry st (src, plain, entries) =
  incr entry_trials;
  write entry_file src;
  Hashtbl.reset mem;
  List.iter (fun (k, v, _) -> Hashtbl.replace mem k v) entries;
  let k, v, refs = List.nth entries (Random.State.int st (List.length entries)) in
  let changed = if Random.State.bool st then mutate_entry st v else (incr sealed_trials; reseal (mutate_tail st v) refs) in
  Hashtbl.replace mem k changed;
  Cache.store := Some store;
  let read w =
    Array.iter
      (fun (md : Types.modul) ->
         Array.iter (function Types.Fun { proto; _ } -> (try read_all proto.func with Pos.Load_error _ -> ()) | _ -> ()) md.cells)
      w.Types.modules
  in
  match
    ignore (Unix.alarm trial_alarm);
    let o = run ~after:read ~no_spec:false entry_file in
    ignore (Unix.alarm 0);
    o
  with
  | exception e ->
    ignore (Unix.alarm 0);
    Cache.store := None;
    Some ("entry exception: " ^ Printexc.to_string e)
  | o ->
    Cache.store := None;
    if o = plain then None else Some (Printf.sprintf "an entry changed the output\n--- without\n%s%s\n--- with\n%s%s" plain.out plain.err o.out o.err)

let args () =
  let seconds = ref 60. and seed = ref 1 and jit = ref false in
  Arg.parse
    [ "--seconds", Arg.Set_float seconds, "duration"; "--seed", Arg.Set_int seed, "seed";
      "--jit", Arg.Set jit, "programs of the shapes the JIT compiles only" ]
    (fun _ -> ())
    "fuzz --seconds N --seed S [--jit]";
  !seconds, !seed, !jit

let () =
  let seconds, seed, jit = args () in
  (* CESIA_JIT=always: the typed path compiles what it can at once, so it is native code against the interpreter. *)
  (* The JIT linked here, given at the first hot unit as the binary's plugin is. *)
  Tier.available := true;
  Tier.loader := Cesia_jit.Engine.install;
  (match Sys.getenv_opt "CESIA_JIT" with
   | Some "always" -> Tier.mode := Tier.always
   | Some "off" -> Tier.mode := Tier.off
   | _ -> ());
  (try Sys.mkdir fail_dir 0o755 with Sys_error _ -> ());
  Array.iter (fun f -> Sys.remove (Filename.concat fail_dir f)) (Sys.readdir fail_dir);
  Sys.set_signal Sys.sigalrm (Sys.Signal_handle (fun _ -> raise Timeout));
  let corpus = corpus () and tomls = toml_corpus () and entries = if jit then [] else entries_corpus () in
  if Array.length corpus = 0 then failwith "no corpus: run from the root of the repository";
  let master = Random.State.make [| seed |] in
  let stop = Unix.gettimeofday () +. seconds in
  let trials = ref 0 and failures = ref 0 in
  let report trial_seed extension src = function
    | None -> ()
    | Some what ->
      incr failures;
      if !failures <= max_saved then begin
        let base = Filename.concat fail_dir (string_of_int !failures) in
        write (base ^ extension) src;
        write (base ^ ".txt") (Printf.sprintf "seed %d\n%s\n" trial_seed what)
      end
  in
  while Unix.gettimeofday () < stop do
    let trial_seed = Random.State.bits master in
    let src = (if jit then shaped else fun st -> generate st corpus) (Random.State.make [| trial_seed |]) in
    incr trials;
    report trial_seed ".ce" src (attempt src);
    if not jit then begin
      let toml = generate_toml (Random.State.make [| trial_seed |]) tomls in
      report trial_seed ".toml" toml (attempt_toml toml);
      if entries <> [] then begin
        let st = Random.State.make [| trial_seed |] in
        let e = List.nth entries (Random.State.int st (List.length entries)) in
        let (src, _, _) = e in
        report trial_seed ".ce" src (attempt_entry st e)
      end
    end
  done;
  Printf.printf "%d trials, %d finished normally, %d toml accepted, %d entries (%d of packages, %d sealed again), %d failures\n"
    !trials !finished !toml_accepted !entry_trials (List.length entries) !sealed_trials !failures;
  if !failures > 0 then exit 1
