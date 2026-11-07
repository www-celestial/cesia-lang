(* The fuzzer: random bytes and mutated valid programs, with strict limits. Only Cesia errors are allowed. The two
   paths, typed and --no-spec, must also give the same result; with CESIA_JIT=always, the typed path runs natively all it
   can. Usage: fuzz.exe --seconds N --seed S, from the
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
  let seconds = ref 60. and seed = ref 1 in
  Arg.parse
    [ "--seconds", Arg.Set_float seconds, "duration"; "--seed", Arg.Set_int seed, "seed" ]
    (fun _ -> ())
    "fuzz --seconds N --seed S";
  !seconds, !seed

let () =
  let seconds, seed = args () in
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
    let src = generate (Random.State.make [| trial_seed |]) corpus in
    incr trials;
    report trial_seed ".ce" src (attempt src);
    let toml = generate_toml (Random.State.make [| trial_seed |]) tomls in
    report trial_seed ".toml" toml (attempt_toml toml)
  done;
  Printf.printf "%d trials, %d finished normally, %d toml accepted, %d failures\n" !trials !finished !toml_accepted
    !failures;
  if !failures > 0 then exit 1
