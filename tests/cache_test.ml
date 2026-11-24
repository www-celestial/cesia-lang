(* OCaml tests of the cache of loaded packages, whose entries are untrusted bytes. An entry whose head is changed, cut,
   grown, of another build or of other sources is not used, never raises, and the package loads as without it, its entry
   written again as it was; a changed file or dependency is read again. A body is read at the first call of its function
   only, from its record, checked then: one damaged, cut or read on another domain is taken from the file resolved again
   from its source, the run goes on with the same output, and the entry is written again. The files of the store: a link
   or an entry open to others is not mapped, and past the limit the entries used least lately go. *)
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

(* Entries in memory, and the number of writes. A record is copied from the entry as it is at that time, as from a file
   that another process changed in place under its mapping. *)
let mem : (string, string) Hashtbl.t = Hashtbl.create 16
let writes = ref 0
let part k off len = String.sub (Option.value (Hashtbl.find_opt mem k) ~default:"") off len
let map k = Option.map (fun s -> String.length s, part k) (Hashtbl.find_opt mem k)
let kept build = Some { Cache.build; map; write = (fun k v -> incr writes; Hashtbl.replace mem k v) }

(* Where the tail of an entry starts. *)
let tail s = if String.length s < 24 then String.length s else 24 + Int64.to_int (String.get_int64_le s 16)

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
      (** Each of xs times k, by a function inside. *)\ndefn Scaled(xs, k)\n  defn by(x)\n    x * k\n  end\n  list.Map(by, xs)\nend\n\n\
      (** A name for n: the long one for a big n only. *)\nNamed(n) = if n > 100 longName(n) else \"small\" end\n\
      longName(n) = \"big, $(further(n))\"\nfurther(n) = \"past $n\"\n\n\
      (** The number of a call it gives back. *)\nWrap(n) = inner(n)\ninner(n) = n + 1\n"
     ^ fill "More");
  write (Filename.concat app "src/units/units.ce") (units "Unit = \" m2\"");
  write (Filename.concat app "loads.ce") "use src/shapes\nuse std/io\n\nio.Print(\"loaded\")\n";
  write (Filename.concat app "main.ce")
    "use src/shapes\nuse std/io\n\nio.Print(shapes.All([shapes.Rect(2, 3), shapes.Rect(4, 5)]))\n\
     add = shapes.Adder(3)\nio.Print(shapes.Fact(10), add(4), shapes.Even(7), shapes.Scaled([1, 2], 3), shapes.Named(3), shapes.Wrap(1))\n\
     io.Print(shapes.Broken(1))\n"

(* The checksum is XXH64: the values of xxhsum -H1, from no byte to more than 32, each way through its loops. *)
let () =
  let text = "Nobody inspects the spammish repetition" in
  let sum s = Printf.sprintf "%016Lx" (Cache.checksum s 0 (String.length s)) in
  check "the checksum of no byte" (sum "" = "ef46db3751d8e999");
  check "the checksum of 3 bytes" (sum "abc" = "44bc2cf5ad770999");
  check "the checksum of 39 bytes" (sum text = "fbcea83c8a378bf1");
  check "the checksum of a part of a text" (Cache.checksum ("xy" ^ text ^ "z") 2 (String.length text) = Cache.checksum text 0 39)

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
  (* A function that gives no number is inferred at its first call only: one that only a function never called calls
     stays unread. One that gives the number of a call keeps its type, an Int. *)
  check "warm: a function that only a function never called calls stays unread" (body "more.ce" "further" = Some false);
  let ret name =
    match Array.find_opt (fun (md : Types.modul) -> String.ends_with ~suffix:"more.ce" md.path) w.modules with
    | Some md ->
      (match md.cells.(List.assoc name md.mnames) with
       | Fun { proto; _ } -> List.map (fun (v : Types.version) -> v.ret) proto.versions
       | _ -> [])
    | None -> []
  in
  check "warm: the number a function gives back through a call keeps its type" (ret "Wrap" = [ Types.TI ]);
  (* The entry of shapes, whose functions main.ce calls. *)
  let holds s t = let n = String.length t in Seq.exists (fun i -> String.sub s i n = t) (Seq.init (String.length s - n + 1) Fun.id) in
  let shapes, good = List.find (fun (_, s) -> holds s "Scaled") entries in
  (* Entries damaged once they were read and checked, every byte of their tails, or cut there: a body read later doesn't
     read as it was written, so it is taken from its file resolved again, the run goes on with the same output, the
     entry goes and is written again when the run ends, from the sources the load read. *)
  let after ?(all = true) name change =
    writes := 0;
    let _, out = world_run ~then_run:(fun () -> Hashtbl.filter_map_inplace (fun _ s -> Some (change s)) mem) "loads.ce" in
    check (name ^ " after the load: the same output") (out = "loaded\n" ^ plain);
    check (name ^ " after the load: the entry goes, then is written again as it was")
      (!writes >= 2 && Hashtbl.find_opt mem shapes = Some good);
    check (name ^ " after the load: the next run the same") (run () = plain);
    if all then
      check (name ^ " after the load: every entry written again as it was")
        (List.for_all (fun (k, good) -> Hashtbl.find_opt mem k = Some good) entries);
    List.iter (fun (k, good) -> Hashtbl.replace mem k good) entries
  in
  (* Damaged in its records alone, an entry whose functions no run calls stays as it is. *)
  after ~all:false "damaged" (fun s -> String.mapi (fun i c -> if i < tail s then c else Char.chr (Char.code c lxor 1)) s);
  after "cut" (fun s -> String.sub s 0 (tail s));
  after "gone" (fun _ -> "");

  (* Each entry damaged, cut and grown: not used, written again as it was; damaged in a record that no run reads, it
     changes nothing and stays until one does. *)
  let again name (k, good) bad =
    Hashtbl.replace mem k bad;
    let out = run () in
    check (name ^ ": the same output") (out = plain);
    let now = Hashtbl.find_opt mem k in
    check (name ^ ": written again as it was")
      (now = Some good || (now = Some bad && String.length bad = String.length good && String.sub bad 0 (tail good) = String.sub good 0 (tail good)));
    Hashtbl.replace mem k good
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
       List.iter (fun cut -> again (Printf.sprintf "cut to %d" cut) (k, good) (String.sub good 0 cut)) [ 0; 1; 8; 15; 16; 17; n / 2; n - 1 ];
       again "a byte added" (k, good) (good ^ "\000");
       again "another entry" (k, good) (snd (List.find (fun (k', _) -> k' <> k) entries)))
    entries;
  (* Another build: none of its entries is read, and it writes its own beside, under other names: two versions used in
     turn don't write over each other's. *)
  writes := 0;
  with_store "other" (fun () -> check "another build: the same output" (run () = plain));
  check "another build: its own entries written" (!writes = List.length entries && Hashtbl.length mem = 2 * List.length entries);
  writes := 0;
  check "back to this build: the same output" (run () = plain);
  check "back to this build: its entries still there, nothing written" (!writes = 0);
  writes := 0;
  with_store "other" (fun () -> check "the other build again: its entries still there" (run () = plain && !writes = 0));
  (* A changed file, then a dependency whose cells move: read again, as without a cache. *)
  let without () = with_store "" (fun () -> Cache.store := None; run ()) in
  write (Filename.concat app "src/units/units.ce") (units "Unit = \" square meters\"");
  let changed = run () in
  check "a changed file is read again" (changed = without () && changed <> plain);
  write (Filename.concat app "src/units/units.ce") (units "First = 1\nSecond = 2\nUnit = \" sq m\"");
  writes := 0;
  let moved = run () in
  check "a dependency whose cells moved: its users resolved again" (moved = without () && !writes = 2)

(* Two programs that use units, which reads only a native of std/list: in one, units loads before the Cesia code of
   std/list and calls into it after; in the other, that code loads first, so units sees the package of std/list grown.
   Each run after the other finds units in its entry, and a changed units is read again in both. *)
let () =
  write (Filename.concat app "later.ce")
    "use src/units\nuse std/list\nuse std/io\n\nio.Print(units.Total([1, 2]), list.Map(x -> x + 1, [1, 2]), units.Unit)\n";
  write (Filename.concat app "first.ce")
    "use std/list\nuse src/units\nuse std/io\n\nio.Print(list.Map(x -> x + 1, [1, 2]), units.Total([1, 2]), units.Unit)\n";
  let alone file =
    let out = Buffer.create 64 in
    let w = Runtime.create_world { Runtime.default_options with o_sink = Buffer.add_string out; o_err = Buffer.add_string out } in
    let code = Loader.run_file w (Filename.concat app file) [] in
    Cache.save ();
    Printf.sprintf "%sexit %d" (Buffer.contents out) code
  in
  let plain file = with_store "" (fun () -> Cache.store := None; alone file) in
  with_store "test" @@ fun () ->
  let later = plain "later.ce" and first = plain "first.ce" in
  ignore (alone "later.ce");
  ignore (alone "first.ce");
  writes := 0;
  let outs = List.map alone [ "later.ce"; "first.ce"; "later.ce"; "first.ce" ] in
  check "two programs in turn: the same outputs as without a cache" (outs = [ later; first; later; first ]);
  check "two programs in turn: nothing resolved again" (!writes = 0);
  write (Filename.concat app "src/units/units.ce") (units "Unit = \" ha\"");
  let later' = plain "later.ce" and first' = plain "first.ce" in
  check "two programs in turn, units changed: read again in both"
    (later' <> later && alone "later.ce" = later' && alone "first.ce" = first' && alone "later.ce" = later')

(* A file of 300 functions, past 256 statements: read from its entry with no young collection, where each of its arrays
   that long, made of a young value, cost one and promoted all that was read, three at each start of Cemacs. *)
let () =
  write (Filename.concat app "src/wide/wide.ce")
    ("(** Many functions. *)\n" ^ String.concat "" (List.init 300 (fun i -> Printf.sprintf "W%d(x) = x + %d   (** W%d. *)\n" i i i)));
  write (Filename.concat app "wide.ce") "use src/wide\nuse std/io\n\nio.Print(wide.W0(1), wide.W299(1))\n";
  let alone () =
    let out = Buffer.create 64 in
    let w = Runtime.create_world { Runtime.default_options with o_sink = Buffer.add_string out; o_err = Buffer.add_string out } in
    let code = Loader.run_file w (Filename.concat app "wide.ce") [] in
    Cache.save ();
    Printf.sprintf "%sexit %d" (Buffer.contents out) code
  in
  with_store "test" @@ fun () ->
  let cold = alone () in
  check "a file of 300 functions runs" (cold = "1 300\nexit 0");
  Gc.set { (Gc.get ()) with minor_heap_size = 1 lsl 21 };
  Gc.minor ();
  let before = (Gc.quick_stat ()).minor_collections in
  let warm = alone () in
  check "a file of 300 functions, from its entry: the same output" (warm = cold);
  check "a file of 300 functions, from its entry: no young collection" ((Gc.quick_stat ()).minor_collections = before)

(* The store's files. *)
let () =
  let cache = Filename.concat top "cache" in
  Unix.putenv "XDG_CACHE_HOME" cache;
  let s = Cesia_sys.Entries.store "b" in
  let load = Filename.concat cache "cesia/load" in
  let entry = Filename.concat load "aa" in
  let read k = Option.map (fun (n, part) -> part 0 n) (s.map k) in
  s.write "aa" "first";
  check "an entry is mapped" (read "aa" = Some "first");
  check "a part of an entry" (Option.map (fun (_, part) -> part 1 3) (s.map "aa") = Some "irs");
  check "no part past its end"
    (match s.map "aa" with
     | Some (n, part) -> List.for_all (fun (off, len) -> match part off len with _ -> false | exception Invalid_argument _ -> true) [ n, 1; -1, 2; 0, n + 1; 2, -1; max_int, 1 ]
     | None -> false);
  let long = String.init 1000 (fun i -> Char.chr (i land 255)) in
  s.write "long" long;
  check "parts of a longer entry, each way through the copy"
    (match s.map "long" with
     | Some (n, part) -> n = 1000 && List.for_all (fun (off, len) -> part off len = String.sub long off len) [ 0, 1000; 1, 999; 3, 31; 5, 32; 7, 65; 999, 1; 1000, 0 ]
     | None -> false);
  s.write "empty" "";
  check "an empty entry is none" (s.map "empty" = None);
  check "the folder is the person's alone" ((Unix.stat load).st_perm = 0o700);
  check "an entry is the person's alone" ((Unix.stat entry).st_perm = 0o600);
  Unix.chmod entry 0o644;
  check "an entry others can read is not used" (read "aa" = None);
  Unix.chmod entry 0o600;
  Unix.rename entry (Filename.concat load "bb");
  Unix.symlink "bb" entry;
  check "a link is not followed" (read "aa" = None);
  s.write "aa" "second";
  check "a write replaces the link, not what it points to"
    ((Unix.lstat entry).st_kind = Unix.S_REG && read "aa" = Some "second" && read "bb" = Some "first");
  (* An entry mapped stays as it was when another run unlinks it or replaces it. *)
  s.write "kept" long;
  (match s.map "kept" with
   | Some (_, part) ->
     s.write "kept" "other";
     let replaced = part 0 1000 in
     Unix.unlink (Filename.concat load "kept");
     check "an entry mapped, then replaced and unlinked, reads as it was" (replaced = long && part 0 1000 = long)
   | None -> check "an entry mapped, then replaced and unlinked, reads as it was" false);
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
  check "under the limit, every entry stays, counted"
    (Cesia_sys.Entries.prune ~limit:1000 dir = 1000 && Array.length (Sys.readdir dir) = 11);
  check "past the limit, the oldest go, down to half" (Cesia_sys.Entries.prune ~limit:800 dir = 400);
  let left = List.sort compare (Array.to_list (Sys.readdir dir)) in
  check "the newest stay" (left = [ "e6"; "e7"; "e8"; "e9"; "new.tmp" ]);
  (* The count of the folder: kept in its file total, it is looked over only when the count would pass the limit. *)
  let total = Filename.concat dir "total" in
  let count () = Int64.to_int (String.get_int64_le (In_channel.with_open_bin total In_channel.input_all) 0) in
  let account n = Cesia_sys.Entries.account ~limit:800 dir n in
  check "no count yet: the folder is looked over" (account 50 && count () = 450);
  write (Filename.concat dir "big") (String.make 1000 'x');
  check "under the limit, the count only grows" (account 100 && count () = 550 && Sys.file_exists (Filename.concat dir "big"));
  check "past it, the folder is pruned and counted again"
    (account 300 && count () = 300 && not (Sys.file_exists (Filename.concat dir "big")));
  (* Runs that end at once: each adds under the lock, and no addition is lost. *)
  let run () = for _ = 1 to 100 do ignore (Cesia_sys.Entries.account ~limit:100000 dir 1) done in
  let kids = List.init 8 (fun _ -> match Unix.fork () with 0 -> run (); Unix._exit 0 | pid -> pid) in
  List.iter (fun pid -> ignore (Unix.waitpid [] pid)) kids;
  check "eight runs at once lose no count" (count () = 1100);
  (* A count spoilt, near the largest number or below zero, is no count: the folder is looked over again. *)
  let spoil v =
    let b = Bytes.create 8 in
    Bytes.set_int64_le b 0 v;
    Out_channel.with_open_bin total (fun o -> Out_channel.output_bytes o b)
  in
  spoil (Int64.of_int max_int);
  check "a count near the largest number is counted again" (account 1 && count () = 1);
  spoil (-5L);
  check "a count below zero is counted again" (account 1 && count () = 1);
  (* A folder just under the limit, whose entry is written again at the same size, goes down to half once, not looked
     over again at each write. *)
  List.iteri
    (fun i name ->
       let path = Filename.concat dir name in
       write path (String.make 100 'x');
       Unix.utimes path (now -. float (10 * (10 - i))) (now -. float (10 * (10 - i))))
    [ "f0"; "f1"; "f2"; "f3"; "f4"; "f5"; "f6" ];
  write (Filename.concat dir "f7") (String.make 90 'x');
  spoil (-1L);
  check "an entry that would pass the limit takes the folder down to half"
    (account 20 && count () = 410 && not (Sys.file_exists (Filename.concat dir "f3")))

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

(* Every package of std/: its functions read from its entry, each body read, are those its sources resolve to, as the
   ones taken when a record doesn't read must be. A program names one function of each, which loads its Cesia code. *)
let () =
  let each = Filename.concat app "each.ce" in
  let first src =
    List.find_map
      (fun line ->
         let line = if String.starts_with ~prefix:"defn " line then String.sub line 5 (String.length line - 5) else line in
         let n = String.length line in
         let rec stop i = if i < n && (match line.[i] with 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true | _ -> false) then stop (i + 1) else i in
         let i = stop 0 in
         if i > 0 && i < n && line.[i] = '(' && (match line.[0] with 'A' .. 'Z' -> true | _ -> false) then Some (String.sub line 0 i)
         else None)
      (String.split_on_char '\n' src)
  in
  let functions name =
    let w = Runtime.create_world { Runtime.default_options with o_sink = ignore; o_err = ignore } in
    let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
    let code = Loader.run_file w each [] in
    Cache.save ();
    let found = ref [] in
    Array.iter
      (fun (md : Types.modul) ->
         if String.ends_with ~suffix:("std/" ^ name ^ ".ce") md.path then
           List.iter
             (fun (text, k) -> match md.cells.(k) with Fun { proto; _ } -> found := (text, proto.func) :: !found | _ -> ())
             md.mnames)
      w.modules;
    code, List.sort compare (List.map fst !found), List.rev !found
  in
  let rec read (f : Ast.func) = Array.iter (fun (p : Ast.param) -> Option.iter expr p.default) f.params; Array.iter expr (Lazy.force f.body)
  and expr (e : Ast.expr) = match e.e with Lambda g | Fn_def (_, g) -> read g | _ -> Resolve.children expr e in
  let tried = ref 0 in
  List.iter
    (fun name ->
       match Option.bind (Embedded.file name) first with
       | None -> ()
       | Some f ->
         write each (Printf.sprintf "use std/%s\n\nx = %s.%s\n" name name f);
         let code, names, plain = with_store "" (fun () -> Cache.store := None; functions name) in
         if code = 0 && plain <> [] then begin
           with_store "test" @@ fun () ->
           ignore (functions name);
           writes := 0;
           let code', names', cached = functions name in
           if List.exists (fun (_, (f : Ast.func)) -> not (Lazy.is_val f.body)) cached then incr tried;
           List.iter (fun (_, f) -> read f) cached;
           List.iter (fun (_, f) -> read f) plain;
           check ("std/" ^ name ^ ": from its entry, the same functions as from its sources")
             (code' = 0 && names' = names && !writes = 0
              && List.for_all (fun (text, f) -> List.assoc_opt text plain = Some f) cached);
           (* Every record damaged once the entry is read: each body is the one of the file resolved again. *)
           let _, _, cached = functions name in
           let unread = List.exists (fun (_, (f : Ast.func)) -> not (Lazy.is_val f.body)) cached in
           let good = Hashtbl.copy mem in
           Hashtbl.filter_map_inplace (fun _ s -> Some (String.mapi (fun i c -> if i < tail s then c else Char.chr (Char.code c lxor 1)) s)) mem;
           writes := 0;
           List.iter (fun (_, f) -> read f) cached;
           check ("std/" ^ name ^ ": every record damaged, the same functions from its sources")
             ((!writes > 0 || not unread) && List.for_all (fun (text, f) -> List.assoc_opt text plain = Some f) cached);
           Hashtbl.reset mem;
           Hashtbl.iter (Hashtbl.replace mem) good
         end
         else check ("std/" ^ name ^ " loads with " ^ f) false)
    (List.filter (fun n -> n <> "natives") Embedded.names);
  check "the packages of std/ compared, each with bodies read at their first need" (!tried >= 30)

(* A body needed on another domain, which never happens: taken from the file resolved again, never raised. Last: no
   fork may follow a domain. *)
let () =
  with_store "test" @@ fun () ->
  ignore (world_run "loads.ce");
  let entries = Hashtbl.fold (fun k v acc -> (k, v) :: acc) mem [] in
  let w, _ = world_run "loads.ce" in
  match Array.find_opt (fun (md : Types.modul) -> String.ends_with ~suffix:"more.ce" md.path) w.modules with
  | Some md ->
    (match md.cells.(List.assoc "More5" md.mnames) with
     | Fun { proto; _ } ->
       let f = proto.func in
       check "a body never needed is not read" (not (Lazy.is_val f.body) && f.var_names = [||]);
       writes := 0;
       let read = Domain.join (Domain.spawn (fun () -> match Lazy.force f.body with b -> Some b | exception _ -> None)) in
       check "a body read on another domain: from its source, with the names of its variables, the entry gone"
         (read <> None && Array.length f.var_names = f.nvars && Array.length f.maybe_undef = f.nvars && !writes = 1);
       Cache.save ();
       check "a body read on another domain: the entries written again as they were"
         (List.for_all (fun (k, good) -> Hashtbl.find_opt mem k = Some good) entries)
     | _ -> check "a body read on another domain: More5 is a function" false)
  | None -> check "a body read on another domain: more.ce is loaded" false

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
