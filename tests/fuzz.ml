(* The fuzzer: random bytes and mutated valid programs, with strict limits. Only Cesia errors are allowed. The two
   paths, typed and --no-spec, must also give the same result; with CESIA_JIT=always, the typed path runs natively all it
   can, and with --jit the programs are of the shapes the JIT compiles, whose loops get hot on the typed path. Usage:
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

let run ~no_spec path =
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

let shaped st = match Random.State.int st 4 with 0 -> csc st | 1 -> thunks st | _ -> odes st

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
  let corpus = corpus () and tomls = toml_corpus () in
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
      report trial_seed ".toml" toml (attempt_toml toml)
    end
  done;
  Printf.printf "%d trials, %d finished normally, %d toml accepted, %d failures\n" !trials !finished !toml_accepted
    !failures;
  if !failures > 0 then exit 1
