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
  Native { nname; perm = Some perm; params = [||]; min_args = 0; max_args = 1; ret_ty = (fun _ -> TA); run; f1 = None; i2 = None }

(* A program, some rights: the exit code, stdout and stderr. *)
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
  Native.register w "ReadIt" (native "ReadIt" Read (fun _ _ -> Text "read"));
  Native.register w "ReadPath"
    (native "ReadPath" Read (fun ctx a ->
         (match a.(0) with
          | Text p -> Runtime.check_perm ctx Read (Some p)
          | _ -> ());
         Text "read"));
  Native.register w "WriteIt" (native "WriteIt" Write (fun _ _ -> Text "written"));
  (* How a map is stored, which a program never sees. *)
  Native.register w "Storage"
    (Native { nname = "Storage"; perm = None; params = [||]; min_args = 1; max_args = 1; ret_ty = (fun _ -> TA); f1 = None;
              i2 = None;
              run = (fun _ a ->
                  Text (match a.(0) with Dict { keys = { deep = Flat; _ }; _ } -> "block" | Dict _ -> "deep" | _ -> "other")) });
  (* Do two maps share their keys? *)
  Native.register w "SameKeys"
    (Native { nname = "SameKeys"; perm = None; params = [||]; min_args = 2; max_args = 2; ret_ty = (fun _ -> TA); f1 = None;
              i2 = None;
              run = (fun _ a ->
                  match a.(0), a.(1) with
                  | Dict { keys = { deep = Flat; _ } as x; _ }, Dict { keys = { deep = Flat; _ } as y; _ } -> if x == y then True else False
                  | _ -> False) });
  let path = Filename.temp_file "cesia" ".ce" in
  Out_channel.with_open_bin path (fun oc -> output_string oc src);
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
  let code, _, err = run "Print(ReadIt())\n" in
  check "denied by default" (code = 1);
  check "exact denial text" (has "Permission \"read\" denied. Run again with --allow read." err);
  let code, out, _ = run ~perms:[ Read, None ] "Print(ReadIt())\n" in
  check "--allow read" (code = 0 && has "read" out);
  let code, _, err = run ~perms:[ Read, None ] "Print(WriteIt())\n" in
  check "read does not grant write" (code = 1 && has "\"write\"" err);
  let code, _, _ = run ~all:true "Print(ReadIt(), WriteIt())\n" in
  check "--allow all" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "Print(ReadPath(\"./data/a.txt\"))\n" in
  check "read=./data inside the folder" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "Print(ReadPath(\"./other/a.txt\"))\n" in
  check "read=./data outside the folder" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "Print(ReadPath(\"./data/../secret.txt\"))\n" in
  check "escape through .. denied" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "Print(ReadPath(\"./data\"))\n" in
  check "read=./data covers the folder itself" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "Print(ReadPath(\"./database/a.txt\"))\n" in
  check "read=./data does not cover ./database" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "Print(ReadPath(\"/etc/passwd\"))\n" in
  check "read=. does not cover an absolute path" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "Print(ReadPath(\"../secret.txt\"))\n" in
  check "read=. does not cover .." (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "Print(ReadPath(\"./a/b.txt\"))\n" in
  check "read=. covers its subfolders" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "/" ] "Print(ReadPath(\"/etc/hosts\"))\n" in
  check "read=/ covers every absolute path" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "/tmp" ] "Print(ReadPath(\"/tmp/../etc/passwd\"))\n" in
  check "read=/tmp denies escape through .." (code = 1);
  let code, _, _ = run "f = ReadIt\nPrint(f())\n" in
  check "also denied through a dynamic call" (code = 1);
  let code, _, _ = run "Print(Map(ReadIt, [1]))\n" in
  check "also denied from the prelude" (code = 1);
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
    "{A: 1}", "block"; "{\"a-b\": 1}", "block"; "{1: 2}", "block"; "Dict()", "block"; "{}", "block";
    "Dict([{Key: \"a\", Value: 1}])", "block"; "Unwrap(json.Parse(\"{\\\"a\\\": 1}\"))", "block";
    "Put(\"A\", 2, {A: 1})", "block"; "Put(\"B\", 2, {A: 1})", "block"; "Drop(\"A\", {A: 1, B: 2})", "block";
    "Fill(0, 2)", "other"; "Ok(1)", "other"; literal 32, "block"; literal 33, "deep"; "Put(\"Z\", 1, " ^ literal 32 ^ ")", "deep";
    "Drop(\"K0\", " ^ literal 33 ^ ")", "deep" ]
  in
  List.iter
    (fun (e, want) ->
       let _, out, err = run ("use json\nPrint(Storage(" ^ e ^ "))\n") in
       check ("storage of " ^ e ^ ": " ^ out ^ err) (out = want ^ "\n"))
    storage;
  let grown n = "m = {}\nfor i in 1:" ^ string_of_int n ^ "\n  k = \"k$(i)\"\n  m[k] = i\nend\nPrint(Storage(m), Len(m))\n" in
  check "32 keys from a variable, a block" (run (grown 32) = (0, "block 32\n", ""));
  check "33 keys from a variable, deeper" (run (grown 33) = (0, "deep 33\n", ""));
  check "maps of one literal share their keys" (run "f(x) = {A: x, B: 2}\nPrint(SameKeys(f(1), f(2)))\n" = (0, "true\n", ""));
  check "a name added at one place shares the keys it gives"
    (run "defn f(x)\n  m = {A: x}\n  m.B = 2\n  m\nend\nPrint(SameKeys(f(1), f(2)), Equal(Keys(f(1)), [\"A\", \"B\"]))\n" = (0, "true true\n", ""));
  check "rows of one JSON share their keys"
    (run "use json\nd = Unwrap(json.Parse(\"[{\\\"a\\\": 1, \\\"b\\\": 2}, {\\\"a\\\": 3, \\\"b\\\": 4}]\"))\nPrint(SameKeys(d[1], d[2]), d[2].b)\n" = (0, "true 4\n", ""));
  check "keys from data share nothing" (run "defn f()\n  m = {}\n  k = \"A\"\n  m[k] = 1\n  m\nend\nPrint(SameKeys(f(), f()))\n" = (0, "false\n", ""));
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
  check "the trie keeps keys, values and order" (model 0x3FFF_FFFF);
  check "the trie with few bits of hash" (model 0x1F);
  check "the trie with equal hashes" (model 0);
  Trie.mask := 0;
  let n = 10_000 and m = ref (Trie.empty ()) in
  for i = 0 to n - 1 do m := Trie.put !m (Trie.hash (Int i)) (Int i) (Int (2 * i)) done;
  let d = ref !m in
  for i = 0 to (n / 2) - 1 do d := Trie.drop !d (Trie.hash (Int i)) (Int i) done;
  check "10,000 keys of one hash"
    (Trie.length !m = n && Trie.find !m 0 (Int 9_999) = Int 19_998 && (Trie.items !m).(2 * (n - 1)) = Int (n - 1)
     && Trie.length !d = n / 2 && Trie.find !d 0 (Int 0) = Undef && (Trie.items !d).(0) = Int (n / 2));
  Trie.mask := 0x3FFF_FFFF;
  let program = "f(x) = x + 1\nPrint(f(1))\n" in
  let code, count = hooks program in
  check "no hooks without --debugger" (code = 0 && count = 0);
  let code, count = hooks ~debugger:() program in
  check "hooks with --debugger" (code = 0 && count > 0);
  if !failures > 0 then exit 1;
  print_endline "engine_test: ok"
