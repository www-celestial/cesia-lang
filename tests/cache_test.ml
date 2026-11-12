(* OCaml tests of the cache of loaded packages, whose entries are untrusted bytes. An entry changed anywhere, cut, grown, of
   another build or of other sources is not used, never raises, and the package loads as without it, its entry written
   again as it was; a changed file or dependency is read again. The files of the store: a link or an entry open to others
   is not read, and past the limit the entries used least lately go. *)
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
let filler = String.concat "" (List.init 12 (fun i -> Printf.sprintf "(** Filler %d, to pass the least size. *)\nFill%d(x) = x + %d\n" i i i))

let () =
  write (Filename.concat app "cesia.toml") "[project]\nname = \"app\"\n";
  write (Filename.concat shapes "area.ce")
    ("(** Areas. *)\nuse src/units\nuse std/list\nuse std/text\n\n(** A rectangle. *)\nstruct Rect { W, H }\n\n\
      (** The area. *)\nArea(r) = r.W * r.H\n\n\
      (** Their areas, in a unit. *)\nAll(rs) = text.Str(list.Sum(list.Map(Area, rs)), units.Unit)\n" ^ filler);
  write (Filename.concat shapes "broken.ce")
    "(** What fails. *)\nuse std/bug\n\n(** A panic, two calls down. *)\nBroken(n) = deeper(n)\n\
     deeper(n) = if n > 0 bug.Panic(\"broken $n\") else 0 end\n";
  write (Filename.concat app "src/units/units.ce") ("(** Units. *)\nUnit = \" m2\"\n" ^ filler);
  write (Filename.concat app "main.ce")
    "use src/shapes\nuse std/io\n\nio.Print(shapes.All([shapes.Rect(2, 3), shapes.Rect(4, 5)]))\nio.Print(shapes.Broken(1))\n"

let run () =
  let out = Buffer.create 256 in
  let w = Runtime.create_world { Runtime.default_options with o_sink = Buffer.add_string out; o_err = Buffer.add_string out } in
  let code = Loader.run_file w (Filename.concat app "main.ce") [] in
  (* What the binary writes when it ends, written here at once. *)
  Cache.save ();
  Printf.sprintf "%sexit %d" (Buffer.contents out) code

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
  check "warm: the same output and error" (run () = plain);
  check "warm: every package from its entry, nothing written" (!writes = 0);
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
  write (Filename.concat app "src/units/units.ce") ("(** Units. *)\nUnit = \" square meters\"\n" ^ filler);
  let changed = run () in
  check "a changed file is read again" (changed = without () && changed <> plain);
  write (Filename.concat app "src/units/units.ce") ("(** Units. *)\nFirst = 1\nSecond = 2\nUnit = \" sq m\"\n" ^ filler);
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
