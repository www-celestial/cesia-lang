(* OCaml tests: the permission mechanism, with natives reserved for tests. *)
open Cesia
open Types

let failures = ref 0

let check name ok =
  if not ok then begin
    incr failures;
    prerr_endline ("FAILED: " ^ name)
  end

let native nname perm run =
  Native { nname; perm = Some perm; params = [||]; min_args = 0; max_args = 1; ret_ty = (fun _ -> TA); run; f1 = None; i2 = None; gives_result = false }

(* A program with the uses of the packages it names, at its end, so that its lines stay as written. *)
let with_uses src =
  let has text =
    let n = String.length src and m = String.length text in
    let rec go i = i + m <= n && (String.sub src i m = text || go (i + 1)) in
    go 0
  in
  let packages = [ "io"; "result"; "bug"; "list"; "matrix"; "text"; "dict"; "math"; "fn"; "value"; "fiber"; "test" ] in
  src ^ String.concat "" (List.map (fun p -> if has ("use std/" ^ p) then "" else "\nuse std/" ^ p) packages) ^ "\n"

(* A program, some rights: the exit code, stdout and stderr. The natives of std/test are reserved for these tests. *)
let run ?(perms = []) ?(all = false) src =
  let out = Buffer.create 64 and err = Buffer.create 64 in
  let options =
    { Runtime.default_options with
      o_grants = { all; perms };
      o_sink = Buffer.add_string out;
      o_err = Buffer.add_string err }
  in
  let w = Runtime.create_world options in
  Loader.init w;
  let natives = ref [] in
  let register name value = natives := (name, value) :: !natives in
  register "ReadIt" (native "ReadIt" Read (fun _ _ -> Text "read"));
  register "ReadPath"
    (native "ReadPath" Read (fun ctx a ->
         (match a.(0) with
          | Text p -> Runtime.check_perm ctx Read (Some p)
          | _ -> ());
         Text "read"));
  register "WriteIt" (native "WriteIt" Write (fun _ _ -> Text "written"));
  (* How a map is stored, which a program never sees. *)
  register "Storage"
    (Native { nname = "Storage"; perm = None; params = [||]; min_args = 1; max_args = 1; ret_ty = (fun _ -> TA); f1 = None;
              i2 = None; gives_result = false;
              run = (fun _ a ->
                  Text (match a.(0) with Dict { keys = { deep = Flat; _ }; _ } -> "block" | Dict _ -> "deep" | _ -> "other")) });
  (* Do two maps share their keys? *)
  register "SameKeys"
    (Native { nname = "SameKeys"; perm = None; params = [||]; min_args = 2; max_args = 2; ret_ty = (fun _ -> TA); f1 = None;
              i2 = None; gives_result = false;
              run = (fun _ a ->
                  match a.(0), a.(1) with
                  | Dict { keys = { deep = Flat; _ } as x; _ }, Dict { keys = { deep = Flat; _ } as y; _ } -> if x == y then True else False
                  | _ -> False) });
  w.native_modules <- ("test", !natives) :: w.native_modules;
  let path = Filename.temp_file "cesia" ".ce" in
  Out_channel.with_open_bin path (fun oc -> output_string oc (with_uses src));
  let code = Loader.run w path [] in
  Sys.remove path;
  code, Buffer.contents out, Buffer.contents err

(* How many hooks a program compiled. *)
let hooks ?debugger src =
  let write path text = Out_channel.with_open_bin path (fun oc -> output_string oc text) in
  let path = Filename.temp_file "cesia" ".ce" in
  write path src;
  let dbg = Filename.temp_file "cesia" ".ce" in
  write dbg "OnStop(stop) = \"continue\"\n";
  let o_debugger = Option.map (fun _ -> dbg) debugger in
  let w =
    Runtime.create_world
      { Runtime.default_options with
        o_debugger;
        o_sink = ignore;
        o_err = ignore }
  in
  let code = Loader.run_file w path [] in
  Sys.remove path;
  Sys.remove dbg;
  code, Debug.hooks_compiled w

let has text s =
  let n = String.length s and m = String.length text in
  let rec go i = i + m <= n && (String.sub s i m = text || go (i + 1)) in
  go 0

(* A folder with these files, removed afterwards. A name ending in / is a folder. *)
let with_tree names f =
  let top = Filename.temp_dir "cesia" "tree" in
  let path n = Filename.concat top n in
  List.iter
    (fun n ->
       if String.ends_with ~suffix:"/" n then Sys.mkdir (path n) 0o755
       else Out_channel.with_open_bin (path n) (fun oc -> output_string oc ""))
    names;
  f top;
  List.iter (fun n -> if String.ends_with ~suffix:"/" n then () else Sys.remove (path n)) names;
  List.iter (fun n -> if String.ends_with ~suffix:"/" n then Sys.rmdir (path n)) (List.rev names);
  Sys.rmdir top

let () =
  with_tree [ "b.ce"; "a.ce"; "c.test.ce"; ".#d.ce"; "notes.txt"; "e.ce/"; "sub/"; "sub/f.ce" ] (fun top ->
      check "a package is its .ce files, in the order of their names"
        (Package.files top = [ Filename.concat top "a.ce"; Filename.concat top "b.ce" ]);
      check "a subfolder is another package" (Package.files (Filename.concat top "sub") = [ Filename.concat top "sub/f.ce" ]));
  with_tree [ "only.test.ce" ] (fun top -> check "tests alone are no package" (Package.files top = []));
  check "a missing folder has no file" (Package.files "/no/such/folder" = []);
  with_tree [ "cesia.toml"; "a/"; "a/b/"; "a/b/c.ce" ] (fun top ->
      let top = Runtime.normalize top in
      check "the root is the folder of cesia.toml, from a file" (Package.root_of (top ^ "/a/b/c.ce") = top);
      check "the root is the folder of cesia.toml, from a folder" (Package.root_of (top ^ "/a/b") = top));
  with_tree [ "x.ce" ] (fun top ->
      let top = Runtime.normalize top in
      check "without cesia.toml, the root is the folder of the file" (Package.root_of (top ^ "/x.ce") = top));
  let here = Sys.getcwd () in
  check "a path under the working directory is shown from it" (Package.shown (here ^ "/a/b.ce") = "a/b.ce");
  check "a path elsewhere stays whole" (Package.shown "/elsewhere/b.ce" = "/elsewhere/b.ce")

let () =
  let code, _, err = run "io.Print(test.ReadIt())\n" in
  check "denied by default" (code = 1);
  check "exact denial text" (has "Permission \"read\" denied. Run again with --allow read." err);
  let code, out, _ = run ~perms:[ Read, None ] "io.Print(test.ReadIt())\n" in
  check "--allow read" (code = 0 && has "read" out);
  let code, _, err = run ~perms:[ Read, None ] "io.Print(test.WriteIt())\n" in
  check "read does not grant write" (code = 1 && has "\"write\"" err);
  let code, _, _ = run ~all:true "io.Print(test.ReadIt(), test.WriteIt())\n" in
  check "--allow all" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "io.Print(test.ReadPath(\"./data/a.txt\"))\n" in
  check "read=./data inside the folder" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "io.Print(test.ReadPath(\"./other/a.txt\"))\n" in
  check "read=./data outside the folder" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "io.Print(test.ReadPath(\"./data/../secret.txt\"))\n" in
  check "escape through .. denied" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "io.Print(test.ReadPath(\"./data\"))\n" in
  check "read=./data covers the folder itself" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "io.Print(test.ReadPath(\"./database/a.txt\"))\n" in
  check "read=./data does not cover ./database" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "io.Print(test.ReadPath(\"/etc/passwd\"))\n" in
  check "read=. does not cover an absolute path" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "io.Print(test.ReadPath(\"../secret.txt\"))\n" in
  check "read=. does not cover .." (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "io.Print(test.ReadPath(\"./a/b.txt\"))\n" in
  check "read=. covers its subfolders" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "/" ] "io.Print(test.ReadPath(\"/etc/hosts\"))\n" in
  check "read=/ covers every absolute path" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "/tmp" ] "io.Print(test.ReadPath(\"/tmp/../etc/passwd\"))\n" in
  check "read=/tmp denies escape through .." (code = 1);
  let code, _, err = run "f = test.ReadIt\nio.Print(f())\n" in
  check "also denied through a dynamic call" (code = 1 && has "Permission \"read\" denied" err);
  let code, _, err = run "io.Print(list.Map(test.ReadIt, [1]))\n" in
  check "also denied from std/list" (code = 1 && has "Permission \"read\" denied" err);
  check "exec is exact" (Runtime.scope_matches Exec "git" "git" && not (Runtime.scope_matches Exec "git" "git2"));
  check "env is exact" (Runtime.scope_matches Env "HOME" "HOME" && not (Runtime.scope_matches Env "HOME" "PATH"));
  check "net port" (Runtime.scope_matches Net ":8080" ":8080" && not (Runtime.scope_matches Net ":8080" ":8081"));
  check "net host" (Runtime.scope_matches Net "a.com" "a.com:443" && not (Runtime.scope_matches Net "a.com" "b.com:443"));
  check "net host and port"
    (Runtime.scope_matches Net "a.com:443" "a.com:443" && not (Runtime.scope_matches Net "a.com:443" "a.com:80"));
  check "net host is no suffix" (not (Runtime.scope_matches Net "a.com" "evil-a.com:443"));
  check "read stays a path" (Runtime.scope_matches Read "./data" "./data/a" && not (Runtime.scope_matches Read "./data" "./b"));
  check "default memory is 80% of the RAM"
    (Runtime.default_memory 1_024_000 = 102_400);
  check "unknown RAM means no limit" (Runtime.default_memory 0 = max_int);
  (* One storage, which a program never sees: one block up to 32 keys, deeper past them, whatever the way a map is made. *)
  let literal n = "{" ^ String.concat ", " (List.init n (fun i -> Printf.sprintf "K%d: %d" i i)) ^ "}" in
  let storage = [
    "{A: 1}", "block"; "{\"a-b\": 1}", "block"; "{1: 2}", "block"; "dict.Dict()", "block"; "{}", "block";
    "dict.Dict([{Key: \"a\", Value: 1}])", "block"; "result.Unwrap(json.Parse(\"{\\\"a\\\": 1}\"))", "block";
    "dict.Put(\"A\", 2, {A: 1})", "block"; "dict.Put(\"B\", 2, {A: 1})", "block"; "dict.Drop(\"A\", {A: 1, B: 2})", "block";
    "list.Fill(0, 2)", "other"; "result.Ok(1)", "other"; literal 32, "block"; literal 33, "deep"; "dict.Put(\"Z\", 1, " ^ literal 32 ^ ")", "deep";
    "dict.Drop(\"K0\", " ^ literal 33 ^ ")", "deep" ]
  in
  List.iter
    (fun (e, want) ->
       let _, out, err = run ("use std/json\nio.Print(test.Storage(" ^ e ^ "))\n") in
       check ("storage of " ^ e ^ ": " ^ out ^ err) (out = want ^ "\n"))
    storage;
  let grown n = "m = {}\nfor i in 1.." ^ string_of_int n ^ "\n  k = \"k$(i)\"\n  m[k] = i\nend\nio.Print(test.Storage(m), value.Len(m))\n" in
  check "32 keys from a variable, a block" (run (grown 32) = (0, "block 32\n", ""));
  check "33 keys from a variable, deeper" (run (grown 33) = (0, "deep 33\n", ""));
  check "maps of one literal share their keys" (run "f(x) = {A: x, B: 2}\nio.Print(test.SameKeys(f(1), f(2)))\n" = (0, "true\n", ""));
  check "a name added at one place shares the keys it gives"
    (run "defn f(x)\n  m = {A: x}\n  m.B = 2\n  m\nend\nio.Print(test.SameKeys(f(1), f(2)), value.Equal(dict.Keys(f(1)), [\"A\", \"B\"]))\n" = (0, "true true\n", ""));
  check "rows of one JSON share their keys"
    (run "use std/json\nd = result.Unwrap(json.Parse(\"[{\\\"a\\\": 1, \\\"b\\\": 2}, {\\\"a\\\": 3, \\\"b\\\": 4}]\"))\nio.Print(test.SameKeys(d[1], d[2]), d[2].b)\n" = (0, "true 4\n", ""));
  check "keys from data share nothing" (run "defn f()\n  m = {}\n  k = \"A\"\n  m[k] = 1\n  m\nend\nio.Print(test.SameKeys(f(), f()))\n" = (0, "false\n", ""));
  (* The trie against a list of keys in the order of insertion, for random puts and drops: with every bit of hash, with 5,
     so that keys meet deep down, and with none, so that every key falls into the tree of equal hashes. *)
  let model mask =
    Trie.mask := mask;
    let rng = Random.State.make [| 1107 |] in
    let key i = if i land 1 = 0 then Int i else Text ("k" ^ string_of_int i) in
    let m = ref (Trie.empty ()) and l = ref [] and ok = ref true in
    for step = 1 to 6_000 do
      let k = key (Random.State.int rng 300) in
      if Random.State.int rng 4 = 0 then begin
        m := Trie.drop !m (Trie.hash k) k;
        l := List.filter (fun (k', _) -> not (Trie.same k k')) !l
      end else begin
        m := Trie.put !m (Trie.hash k) k (Int step);
        l := if List.exists (fun (k', _) -> Trie.same k k') !l then List.map (fun (k', v) -> if Trie.same k k' then k', Int step else k', v) !l
          else !l @ [ (k, Int step) ]
      end;
      if Trie.length !m <> List.length !l then ok := false;
      if step mod 500 = 0 then begin
        let o = Trie.items !m in
        if Array.to_list o <> List.concat_map (fun (k, v) -> [ k; v ]) !l then ok := false;
        List.iter (fun (k, v) -> if Trie.find !m (Trie.hash k) k <> v then ok := false) !l
      end
    done;
    Trie.mask := 0x3FFF_FFFF;
    !ok
  in
  (* Old maps stay as they were: puts and drops from any earlier version, keys that grew in place included. *)
  let versions mask =
    Trie.mask := mask;
    let rng = Random.State.make [| 2026 |] in
    let all = Array.make 2_000 (Trie.empty (), []) and n = ref 1 and ok = ref true in
    for step = 1 to 1_999 do
      let m, l = all.(Random.State.int rng !n) in
      let k = Text ("k" ^ string_of_int (Random.State.int rng 60)) in
      let v =
        if Random.State.int rng 5 = 0 then Trie.drop m (Trie.hash k) k, List.filter (fun (k', _) -> not (Trie.same k k')) l
        else if List.exists (fun (k', _) -> Trie.same k k') l then
          Trie.put m (Trie.hash k) k (Int step), List.map (fun (k', x) -> if Trie.same k k' then k', Int step else k', x) l
        else (if step land 1 = 0 then Trie.put_owned (Trie.own_copy m) else Trie.put m) (Trie.hash k) k (Int step), l @ [ (k, Int step) ]
      in
      all.(!n) <- v;
      incr n
    done;
    Array.iter
      (fun (m, l) ->
         if Array.to_list (Trie.items m) <> List.concat_map (fun (k, v) -> [ k; v ]) l then ok := false;
         List.iter (fun (k, v) -> if Trie.find m (Trie.hash k) k <> v then ok := false) l)
      all;
    Trie.mask := 0x3FFF_FFFF;
    !ok
  in
  check "old maps keep their keys" (versions 0x3FFF_FFFF);
  check "old maps keep their keys, few bits of hash" (versions 0x7);
  (* A map that adds and drops keys for long renumbers its ranks and keeps its order: with a limit of 100, every few dozen
     writes, owned or not. *)
  let renumbered () =
    Trie.rank_limit := 100;
    let rng = Random.State.make [| 33 |] in
    let key i = Text ("r" ^ string_of_int i) in
    let m = ref (Trie.empty ()) and l = ref [] and ok = ref true in
    for i = 0 to 39 do
      m := Trie.put_owned !m (Trie.hash (key i)) (key i) (Int i);
      l := !l @ [ (key i, Int i) ]
    done;
    for step = 1 to 3_000 do
      let k = key (Random.State.int rng 40) in
      m := Trie.drop !m (Trie.hash k) k;
      l := List.filter (fun (k', _) -> not (Trie.same k k')) !l;
      m := (if step land 1 = 0 then Trie.put_owned else Trie.put) !m (Trie.hash k) k (Int step);
      l := !l @ [ (k, Int step) ];
      if Array.to_list (Trie.items !m) <> List.concat_map (fun (k, v) -> [ k; v ]) !l then ok := false;
      (match !m with Dict { keys = { deep = Deep d; _ }; _ } when d.next < 100 -> () | _ -> ok := false)
    done;
    Trie.rank_limit := 1 lsl 32;
    !ok
  in
  check "ranks renumbered keep the order" (renumbered ());
  (* Keys that differ only in the 64th bit of each word of 8 bytes, which JSON lets through: they spread. *)
  let crafted = Array.init 16_384 (fun k -> String.concat "" (List.init 14 (fun w -> "abcdefg" ^ String.make 1 (if k land (1 lsl w) <> 0 then '\xc1' else 'A')))) in
  let seen = Hashtbl.create 16_384 in
  Array.iter (fun s -> Hashtbl.replace seen (Trie.hash (Text s)) ()) crafted;
  check "keys that differ in the top bit of their words spread" (Hashtbl.length seen > 16_300);
  (* 14 blocks of "Aa" or "BB": one value under h * 31 + c, the hash the columns had; spread under the trie's. *)
  let blocks = Array.init 16_384 (fun k -> String.concat "" (List.init 14 (fun b -> if k land (1 lsl b) <> 0 then "Aa" else "BB"))) in
  let poly s = String.fold_left (fun h c -> (h * 31) + Char.code c) 0 s in
  check "the blocks collide under a polynomial hash" (Array.for_all (fun s -> poly s = poly blocks.(0)) blocks);
  let distinct f = let seen = Hashtbl.create 16_384 in Array.iter (fun s -> Hashtbl.replace seen (f s) ()) blocks; Hashtbl.length seen in
  check "the blocks spread under the trie's hash"
    (distinct Trie.hash_text > 16_300 && distinct (fun s -> Trie.hash_text s land 0x7FFF) > 12_000);
  let ints = [ 0; -1; max_int; min_int; (1 lsl 53) - 1; 1 lsl 53; (1 lsl 53) + 1; -(1 lsl 53) - 1 ] in
  check "hash_int is the hash of an Int" (List.for_all (fun i -> Trie.hash_int i = Trie.hash (Int i)) ints);
  check "hash_float is the hash of a Float"
    (List.for_all (fun f -> Trie.hash_float f = Trie.hash (Float f)) [ 1.0; -0.0; 0.5; Float.nan; 1e300; 9007199254740992.0 ]
     && Trie.hash_float 1.0 = Trie.hash (Int 1) && Trie.hash_float (-0.0) = Trie.hash (Int 0)
     && Trie.hash_float 9007199254740992.0 = Trie.hash (Int ((1 lsl 53) + 1)));
  check "hash_text is the hash of a Text"
    (List.for_all (fun s -> Trie.hash_text s = Trie.hash (Text s)) [ ""; "abcdefg"; "abcdefgh"; "abcdefghi" ]);
  check "the trie keeps keys, values and order" (model 0x3FFF_FFFF);
  check "the trie with few bits of hash" (model 0x1F);
  check "the trie with equal hashes" (model 0);
  (* Thousands of keys, so that nodes meet several levels down and drops bring keys back inline: puts in place and not,
     drops, against a table of keys stamped in the order they came. *)
  let big mask =
    Trie.mask := mask;
    let rng = Random.State.make [| 4242 |] in
    let key i = if i mod 3 = 0 then Int i else Text ("b" ^ string_of_int i) in
    let tbl = Hashtbl.create 16 and stamp = ref 0 and m = ref (Trie.empty ()) and ok = ref true in
    for step = 1 to 40_000 do
      let i = Random.State.int rng 6_000 in
      let k = key i in
      (match Random.State.int rng 5 with
       | 0 ->
         m := Trie.drop !m (Trie.hash k) k;
         Hashtbl.remove tbl i
       | 1 -> m := Trie.put !m (Trie.hash k) k (Int step)
       | _ -> m := Trie.put_owned (Trie.own_copy !m) (Trie.hash k) k (Int step));
      (match Random.State.int rng 5 with
       | 0 -> ()
       | _ when Hashtbl.mem tbl i -> if Trie.find !m (Trie.hash k) k == Undef then ok := false
       | _ -> ());
      (match Trie.find !m (Trie.hash k) k with
       | Int v when v = step -> (match Hashtbl.find_opt tbl i with Some (st, _) -> Hashtbl.replace tbl i (st, step) | None -> incr stamp; Hashtbl.replace tbl i (!stamp, step))
       | Undef -> if Hashtbl.mem tbl i then ok := false
       | _ -> if not (Hashtbl.mem tbl i) then ok := false);
      if Trie.length !m <> Hashtbl.length tbl then ok := false;
      if step mod 4_000 = 0 then begin
        let want = List.sort compare (Hashtbl.fold (fun i (st, v) acc -> (st, i, v) :: acc) tbl []) in
        let got = Trie.items !m in
        if Array.length got <> 2 * List.length want then ok := false
        else List.iteri (fun j (_, i, v) -> if not (Trie.same got.(2 * j) (key i)) || got.((2 * j) + 1) <> Int v then ok := false) want
      end
    done;
    Trie.mask := 0x3FFF_FFFF;
    !ok
  in
  check "the trie of thousands of keys" (big 0x3FFF_FFFF);
  check "the trie of thousands of keys, 10 bits of hash" (big 0x3FF);
  Trie.mask := 0;
  let n = 10_000 and m = ref (Trie.empty ()) in
  for i = 0 to n - 1 do m := Trie.put !m (Trie.hash (Int i)) (Int i) (Int (2 * i)) done;
  let d = ref !m in
  for i = 0 to (n / 2) - 1 do d := Trie.drop !d (Trie.hash (Int i)) (Int i) done;
  check "10,000 keys of one hash"
    (Trie.length !m = n && Trie.find !m 0 (Int 9_999) = Int 19_998 && (Trie.items !m).(2 * (n - 1)) = Int (n - 1)
     && Trie.length !d = n / 2 && Trie.find !d 0 (Int 0) = Undef && (Trie.items !d).(0) = Int (n / 2));
  Trie.mask := 0x3FFF_FFFF;
  (* A deep map that only one name holds is a table: puts in place against a list of keys in their order, integer values
     then texts, which change its store; and with few bits of hash, or none, its probes run long and it becomes the trie
     while it is written. A copy taken by a persistent put keeps what it had while the table goes on. *)
  let is_table m = match m with Dict { keys = { deep = Deep { root = Table _; _ }; _ }; _ } -> true | _ -> false in
  let owned mask =
    Trie.mask := mask;
    let rng = Random.State.make [| 77 |] in
    let key i = if i land 1 = 0 then Int i else Text ("t" ^ string_of_int i) in
    (* The model: each key's number, its rank and its value. *)
    let m = ref (Trie.empty ()) and tbl = Hashtbl.create 16 and ok = ref true and table_at = ref false and snaps = ref [] in
    let listed () =
      List.map (fun (_, i, v) -> key i, v) (List.sort compare (Hashtbl.fold (fun i (r, v) acc -> (r, i, v) :: acc) tbl []))
    in
    for step = 1 to 8_000 do
      let i = Random.State.int rng 1_500 in
      let k = key i and v = if step < 5_000 then Int step else Text (string_of_int step) in
      m := Trie.put_owned !m (Trie.hash k) k v;
      Hashtbl.replace tbl i ((match Hashtbl.find_opt tbl i with Some (r, _) -> r | None -> step), v);
      if Trie.length !m <> Hashtbl.length tbl then ok := false;
      if step mod 1_000 = 0 then begin
        let l = listed () in
        if Array.to_list (Trie.items !m) <> List.concat_map (fun (k, v) -> [ k; v ]) l then ok := false;
        List.iter (fun (k, v) -> if Trie.find !m (Trie.hash k) k <> v then ok := false) l
      end;
      if step = 6_000 then begin
        table_at := is_table !m;
        let x = Text "snap" and l = listed () in
        snaps := (Trie.put !m (Trie.hash x) x (Int step), List.rev ((x, Int step) :: List.rev l)) :: (!m, l) :: !snaps;
        m := Trie.own_copy !m
      end
    done;
    List.iter (fun (s, l) -> if Array.to_list (Trie.items s) <> List.concat_map (fun (k, v) -> [ k; v ]) l then ok := false) !snaps;
    Trie.mask := 0x3FFF_FFFF;
    !ok, !table_at
  in
  check "an owned table keeps keys, values and order, and a copy what it had" (owned 0x3FFF_FFFF = (true, true));
  check "an owned table with few bits of hash" (fst (owned 0x3F));
  check "an owned table of one hash becomes the trie" (owned 0 = (true, false));
  let fresh n = let m = ref (Trie.empty ()) in for i = 0 to n - 1 do m := Trie.put_owned !m (Trie.hash (Int i)) (Int i) (Int i) done; !m in
  let big = fresh 30_000 in
  let before = Trie.items big in
  let p = Trie.put big (Trie.hash (Int (-1))) (Int (-1)) (Int 0) in
  check "a table written after it was shared becomes the trie, the same keys in the same order"
    (is_table (fresh 33) && (not (is_table big)) && Trie.items big = before && Trie.length p = 30_001
     && Trie.find p (Trie.hash (Int 29_999)) (Int 29_999) = Int 29_999 && Trie.find big (Trie.hash (Int (-1))) (Int (-1)) = Undef);
  let items = Array.concat (List.init 100 (fun i -> [| Text ("o" ^ string_of_int (i mod 70)); Int i |])) in
  let o = Trie.of_items items in
  check "a map of items past a block is a table: a key twice keeps its first place and its last value"
    (is_table o && Trie.length o = 70 && (Trie.items o).(0) = Text "o0" && Trie.find o (Trie.hash (Text "o5")) (Text "o5") = Int 75);
  let program = "use std/io\nf(x) = x + 1\nio.Print(f(1))\n" in
  let code, count = hooks program in
  check "no hooks without --debugger" (code = 0 && count = 0);
  let code, count = hooks ~debugger:() program in
  check "hooks with --debugger" (code = 0 && count > 0);
  (* The verdicts of a test file, rewritten: in each function, each node has its own id, under its count. *)
  let src =
    "use std/list\nuse std/value\nuse std/test\nf(x) = x\nisA() = f(1) == 2 and list.All([f(2) > 1, not value.Equal(f([1]), [f(3)])])\n\
     defn isB()\n  x = f(2)?\n  if x > 1\n    return f(x)[1] == x\n  end\n  test.ForAll(y -> f(y) + it.K == y, list.Map(it + 1, [1]))\nend\n"
  in
  let fn = Parser.program ~file:"a.test.ce" ~nesting:100 (Lexer.tokens ~file:"a.test.ce" src) in
  let notes = Cesia_testing.Verdict.rewrite fn in
  let ok = ref true in
  let rec func (f : Ast.func) =
    let seen = Hashtbl.create 64 in
    let rec walk (e : Ast.expr) =
      if e.id >= f.nnodes || Hashtbl.mem seen e.id then ok := false;
      Hashtbl.replace seen e.id ();
      (match e.e with Lambda g | Fn_def (_, g) -> func g | _ -> ());
      Resolve.children walk e
    in
    Array.iter walk (Lazy.force f.body)
  in
  func fn;
  check "a rewritten verdict keeps unique ids under nnodes" (!ok && Array.length notes > 10);
  (* Two runs in one process, as the fuzzer and the workers of cesia test make: each starts from the seed of the process. *)
  let draws = "use std/random\nio.Print([random.Int(1, 1000) for k in 1..20], random.Float(), random.Shuffle(1..9))\n" in
  let _, first, _ = run draws in
  let _, between, _ = run draws in
  let _, again, _ = run draws in
  check "each run draws the same numbers from the seed" (first = again && between = first && String.length first > 40);
    if !failures > 0 then exit 1;
  print_endline "engine_test: ok"
