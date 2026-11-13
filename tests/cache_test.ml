(* OCaml tests of the cache of loaded packages, whose entries are untrusted bytes. An entry changed anywhere, cut, grown, of
   another build or of other sources is not used, never raises, and the package loads as without it, its entry written
   again as it was; a changed file or dependency is read again. A body is read at the first call of its function only, and
   one damaged in memory after the entry was checked is refused at that call. The files of the store: a link or an entry
   open to others is not read, and past the limit the entries used least lately go. *)
open Cesia

let failures = ref 0

let check name ok =
  if not ok then begin
    incr failures;
    prerr_endline ("FAILED: " ^ name)
  end

let top = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "cesia-cache-test-%d" (Unix.getpid ()))

let write path text =
  let rec make d = if not (Sys.file_exists d) then (make (Filename.dirname d); Sys.mkdir d 0o700) in
  make (Filename.dirname path);
  Out_channel.with_open_bin path (fun oc -> output_string oc text)

(* Entries in memory, and the number of writes. *)
let mem : (string, string) Hashtbl.t = Hashtbl.create 16
let writes = ref 0
let kept build = Some { Cache.build; read = Hashtbl.find_opt mem; write = (fun k v -> incr writes; Hashtbl.replace mem k v) }

let app = Filename.concat top "app"
let shapes = Filename.concat app "src/shapes"
let fill name = String.concat "" (List.init 12 (fun i -> Printf.sprintf "(** Filler %d, to pass the least size. *)\n%s%d(x) = x + %d\n" i name i i))
let filler = fill "Fill"

(* units reads only a native of std/list, before shapes loads the Cesia code of std/list too: the package of std/list grows
   between the two, and an entry must place its modules as they were when it was resolved. *)
let units text = "(** Units. *)\nuse std/list\n\n" ^ text ^ "\n(** A total. *)\nTotal(xs) = list.Sum(xs)\n" ^ filler

let () =
  write (Filename.concat app "cesia.toml") "[project]\nname = \"app\"\n";
  write (Filename.concat shapes "area.ce")
    ("(** Areas. *)\nuse src/units\nuse std/list\nuse std/text\n\n(** A rectangle. *)\nstruct Rect { W, H }\n\n\
      (** The area. *)\nArea(r) = r.W * r.H\n\n\
      (** Their areas, in a unit. *)\nAll(rs) = text.Str(list.Sum(list.Map(Area, rs)), units.Unit)\n" ^ filler);
  write (Filename.concat shapes "broken.ce")
    "(** What fails. *)\nuse std/bug\n\n(** A panic, two calls down. *)\nBroken(n) = deeper(n)\n\
     deeper(n) = if n > 0 bug.Panic(\"broken $n\") else 0 end\n";
  write (Filename.concat shapes "more.ce")
    ("(** Recursion and closures. *)\nuse std/list\n\n(** A factorial. *)\nFact(n) = if n < 2 1 else n * Fact(n - 1) end\n\n\
      (** A function that adds n. *)\nAdder(n) = x -> x + n\n\n\
      (** Even, through odd. *)\nEven(n) = if n == 0 true else odd(n - 1) end\nodd(n) = if n == 0 false else Even(n - 1) end\n\n\
      (** Each of xs times k, by a function inside. *)\ndefn Scaled(xs, k)\n  defn by(x)\n    x * k\n  end\n  list.Map(by, xs)\nend\n"
     ^ fill "More");
  write (Filename.concat app "src/units/units.ce") (units "Unit = \" m2\"");
  write (Filename.concat app "loads.ce") "use src/shapes\nuse std/io\n\nio.Print(\"loaded\")\n";
  write (Filename.concat app "main.ce")
    "use src/shapes\nuse std/io\n\nio.Print(shapes.All([shapes.Rect(2, 3), shapes.Rect(4, 5)]))\n\
     add = shapes.Adder(3)\nio.Print(shapes.Fact(10), add(4), shapes.Even(7), shapes.Scaled([1, 2], 3))\n\
     io.Print(shapes.Broken(1))\n"

(* A run in a world of its own, which it gives with its output. *)
let world_run ?(then_run = ignore) file =
  let out = Buffer.create 256 in
  let w = Runtime.create_world { Runtime.default_options with o_sink = Buffer.add_string out; o_err = Buffer.add_string out } in
  let code = Loader.run_file w (Filename.concat app file) [] in
  then_run ();
  let code = if file = "main.ce" then code else Loader.run w (Filename.concat app "main.ce") [] in
  (* What the binary writes when it ends, written here at once. *)
  Cache.save ();
  w, Printf.sprintf "%sexit %d" (Buffer.contents out) code

let run () = snd (world_run "main.ce")

let with_store build f =
  let saved = !Cache.store in
  Cache.store := kept build;
  Fun.protect ~finally:(fun () -> Cache.store := saved) f

let () =
  let plain = with_store "" (fun () -> Cache.store := None; run ()) in
  check "the program runs and fails as written" (String.length plain > 20 && String.ends_with ~suffix:"exit 1" plain);
  with_store "test" @@ fun () ->
  let cold = run () in
  check "cold: the same output and error as without a cache" (cold = plain);
  let entries = Hashtbl.fold (fun k v acc -> (k, v) :: acc) mem [] in
  check "cold: shapes, units and std/list saved" (List.length entries >= 3);
  writes := 0;
  let w, warm = world_run "main.ce" in
  check "warm: the same output and error" (warm = plain);
  check "warm: every package from its entry, nothing written" (!writes = 0);
  (* The body of a function is read at its first call: the fillers, never called, stay unread. *)
  let body file name =
    match Array.find_opt (fun (md : Types.modul) -> String.ends_with ~suffix:file md.path) w.modules with
    | Some md -> (match md.cells.(List.assoc name md.mnames) with Fun { proto; _ } -> Some (Lazy.is_val proto.func.body) | _ -> None)
    | None -> None
  in
  check "warm: the bodies of the functions called are read"
    (List.for_all (fun name -> body "more.ce" name = Some true) [ "Fact"; "Adder"; "Even"; "odd"; "Scaled" ]
     && body "area.ce" "All" = Some true && body "area.ce" "Area" = Some true);
  check "warm: the bodies of the functions never called stay unread"
    (body "area.ce" "Fill0" = Some false && body "more.ce" "More11" = Some false);
  (* An entry damaged in memory once it was read and checked, which no digest can see: the body read later doesn't read
     as it was written, so the first call of its function stops the program with an error there, the entry goes, and the
     next run reads the package from its sources. *)
  Hashtbl.filter_map_inplace (fun _ s -> Some (Bytes.to_string (Bytes.of_string s))) mem;
  let damage () = Hashtbl.iter (fun _ s -> let b = Bytes.unsafe_of_string s in Bytes.fill b 24 (Bytes.length b - 24) '\255') mem in
  let _, damaged = world_run ~then_run:damage "loads.ce" in
  check "damaged after the load: refused at the first call, with an error at the function"
    (String.starts_with ~prefix:"loaded\n" damaged && String.ends_with ~suffix:"exit 1" damaged
     && List.exists (fun l -> String.ends_with ~suffix:(Messages.cache_damaged.text) l) (String.split_on_char '\n' damaged));
  check "damaged after the load: the entry goes" (Hashtbl.fold (fun _ s n -> if s = "" then n + 1 else n) mem 0 >= 1);
  check "damaged after the load: the next run as without a cache" (run () = plain);
  check "damaged after the load: written again as it was" (List.for_all (fun (k, good) -> Hashtbl.find_opt mem k = Some good) entries);
  (* Each entry damaged, cut and grown: not used, written again as it was. *)
  let again name (k, good) bad =
    Hashtbl.replace mem k bad;
    let out = run () in
    check (name ^ ": the same output") (out = plain);
    check (name ^ ": written again as it was") (Hashtbl.find_opt mem k = Some good)
  in
  List.iter
    (fun (k, good) ->
       let n = String.length good in
       for i = 0 to min n 60 - 1 do
         let i = if n > 60 then i * n / 60 else i in
         let b = Bytes.of_string good in
         Bytes.set b i (Char.chr (Char.code good.[i] lxor (1 lsl (i mod 8))));
         again (Printf.sprintf "byte %d of %d changed" i n) (k, good) (Bytes.to_string b)
       done;
       List.iter (fun cut -> again (Printf.sprintf "cut to %d" cut) (k, good) (String.sub good 0 cut)) [ 0; 1; 8; 23; 24; 25; n / 2; n - 1 ];
       again "a byte added" (k, good) (good ^ "\000");
       again "another entry" (k, good) (snd (List.find (fun (k', _) -> k' <> k) entries)))
    entries;
  (* Another build: none of its entries is read. *)
  writes := 0;
  with_store "other" (fun () -> check "another build: the same output" (run () = plain));
  check "another build: every entry written again" (!writes = List.length entries);
  writes := 0;
  check "back to this build: the same output" (run () = plain);
  check "back to this build: written again" (!writes = List.length entries);
  (* A changed file, then a dependency whose cells move: read again, as without a cache. *)
  let without () = with_store "" (fun () -> Cache.store := None; run ()) in
  write (Filename.concat app "src/units/units.ce") (units "Unit = \" square meters\"");
  let changed = run () in
  check "a changed file is read again" (changed = without () && changed <> plain);
  write (Filename.concat app "src/units/units.ce") (units "First = 1\nSecond = 2\nUnit = \" sq m\"");
  writes := 0;
  let moved = run () in
  check "a dependency whose cells moved: its users resolved again" (moved = without () && !writes = 2)

(* The store's files. *)
let () =
  let cache = Filename.concat top "cache" in
  Unix.putenv "XDG_CACHE_HOME" cache;
  let s = Cesia_sys.Entries.store "b" in
  let load = Filename.concat cache "cesia/load" in
  let entry = Filename.concat load "aa" in
  s.write "aa" "first";
  check "an entry is read" (s.read "aa" = Some "first");
  check "the folder is the person's alone" ((Unix.stat load).st_perm = 0o700);
  check "an entry is the person's alone" ((Unix.stat entry).st_perm = 0o600);
  Unix.chmod entry 0o644;
  check "an entry others can read is not used" (s.read "aa" = None);
  Unix.chmod entry 0o600;
  Unix.rename entry (Filename.concat load "bb");
  Unix.symlink "bb" entry;
  check "a link is not followed" (s.read "aa" = None);
  s.write "aa" "second";
  check "a write replaces the link, not what it points to"
    ((Unix.lstat entry).st_kind = Unix.S_REG && s.read "aa" = Some "second" && s.read "bb" = Some "first");
  (* The limit: the entries used least lately go first, down to half of it; an old temporary file goes. *)
  let dir = Filename.concat top "prune" in
  Sys.mkdir dir 0o700;
  let now = Unix.time () in
  List.iteri
    (fun i name ->
       let path = Filename.concat dir name in
       write path (String.make 100 'x');
       Unix.utimes path (now -. float (10 * (10 - i))) (now -. float (10 * (10 - i))))
    [ "e0"; "e1"; "e2"; "e3"; "e4"; "e5"; "e6"; "e7"; "e8"; "e9" ];
  write (Filename.concat dir "old.tmp") "x";
  Unix.utimes (Filename.concat dir "old.tmp") (now -. 200000.) (now -. 200000.);
  write (Filename.concat dir "new.tmp") "x";
  Cesia_sys.Entries.prune ~limit:1000 dir;
  check "under the limit, every entry stays" (Array.length (Sys.readdir dir) = 11);
  Cesia_sys.Entries.prune ~limit:800 dir;
  let left = List.sort compare (Array.to_list (Sys.readdir dir)) in
  check "past the limit, the oldest go, down to half" (left = [ "e6"; "e7"; "e8"; "e9"; "new.tmp" ])

(* The copy that writes the entries at the end of a run: the program's descriptors are closed in it before anything else,
   so a pipe ends, a port is free and nothing is written where the program writes, while the copy still runs. *)
let () =
  let r, w = Unix.pipe () in
  let listener = Unix.socket PF_INET SOCK_STREAM 0 in
  Unix.setsockopt listener SO_REUSEADDR true;
  Unix.bind listener (ADDR_INET (Unix.inet_addr_loopback, 0));
  Unix.listen listener 8;
  let port = match Unix.getsockname listener with ADDR_INET (_, p) -> p | _ -> 0 in
  let marker = Filename.concat top "copy" in
  Cesia_sys.Entries.after (fun () ->
      let still = match Unix.fstat w with _ -> "open" | exception Unix.Unix_error _ -> "closed" in
      write (marker ^ ".new") still;
      Sys.rename (marker ^ ".new") marker;
      Unix.sleepf 1.);
  Unix.close w;
  Unix.close listener;
  let again = Unix.socket PF_INET SOCK_STREAM 0 in
  check "the port of a listener is free at once"
    (match Unix.bind again (ADDR_INET (Unix.inet_addr_loopback, port)); Unix.listen again 8 with
     | () -> true
     | exception Unix.Unix_error _ -> false);
  Unix.close again;
  let t = Unix.gettimeofday () in
  let ended = Unix.read r (Bytes.create 1) 0 1 = 0 in
  check "the end of a pipe doesn't wait for the copy" (ended && Unix.gettimeofday () -. t < 0.5);
  let rec wait n = if n > 0 && not (Sys.file_exists marker) then (Unix.sleepf 0.01; wait (n - 1)) in
  wait 500;
  check "the copy holds none of the program's descriptors"
    (Sys.file_exists marker && In_channel.with_open_bin marker In_channel.input_all = "closed")

let () =
  let rec remove path =
    match Unix.lstat path with
    | { st_kind = S_DIR; _ } -> Array.iter (fun n -> remove (Filename.concat path n)) (Sys.readdir path); Unix.rmdir path
    | _ -> Unix.unlink path
    | exception Unix.Unix_error _ -> ()
  in
  remove top;
  if !failures > 0 then exit 1;
  print_endline "cache_test: ok"
