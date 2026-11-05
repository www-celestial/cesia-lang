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
                  Text (match a.(0) with Dict _ -> "tree" | Struct { shape = { sname = None; _ }; _ } -> "flat" | _ -> "other")) });
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
  let storage = [
    "{A: 1}", "flat"; "{\"a-b\": 1}", "flat"; "{1: 2}", "tree"; "Dict()", "tree"; "{}", "flat";
    "Dict([{Key: \"a\", Value: 1}])", "tree"; "Unwrap(json.Parse(\"{\\\"a\\\": 1}\"))", "tree";
    "Put(\"A\", 2, {A: 1})", "flat"; "Put(\"B\", 2, {A: 1})", "tree"; "Drop(\"A\", {A: 1, B: 2})", "tree";
    "Drop(\"Z\", {A: 1})", "flat"; "Fill(0, 2)", "other"; "Ok(1)", "other";
    "{A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, I: 9, J: 10, K: 11, L: 12, M: 13, N: 14, O: 15, P: 16}", "flat";
    "{A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, I: 9, J: 10, K: 11, L: 12, M: 13, N: 14, O: 15, P: 16, Q: 17}", "tree" ]
  in
  List.iter
    (fun (e, want) ->
       let _, out, err = run ("use json\nPrint(Storage(" ^ e ^ "))\n") in
       check ("storage of " ^ e ^ ": " ^ out ^ err) (out = want ^ "\n"))
    storage;
  let grown = "m = {A: 1}\nm.B = 2\nm[\"C\"] = 3\nPrint(Storage(m))\nk = \"D\"\nm[k] = 4\nPrint(Storage(m))\n" in
  check "names of the code keep a map flat, a key from a variable makes a tree" (run grown = (0, "flat\ntree\n", ""));
  let written = "m = {A: 1}\nk = \"A\"\nm[k] = 2\nPrint(Storage(m))\nm.A = 3\nPrint(Storage(m))\n" in
  check "writing a key that is there keeps a map flat" (run written = (0, "flat\nflat\n", ""));
  let names = List.init 16 (fun i -> Printf.sprintf "m.K%d = %d\n" i i) in
  check "past 16 keys, a tree" (run ("m = {}\n" ^ String.concat "" names ^ "Print(Storage(m))\nm.Z = 1\nPrint(Storage(m))\n") = (0, "flat\ntree\n", ""));
  (* 700 maps of 15 names of the code: past 10,000 shapes, a new name makes a tree, and a known one still a shape. *)
  let many = List.init 700 (fun i -> "m = {}\n" ^ String.concat "" (List.init 15 (fun j -> Printf.sprintf "m.F%dx%d = 1\n" i j))) in
  let capped = String.concat "" many ^ "n = {}\nn.Zed = 1\nPrint(Storage(n))\nn = {}\nn.F0x0 = 1\nPrint(Storage(n))\n" in
  check "past 10,000 shapes, new maps are trees" (run capped = (0, "tree\nflat\n", ""));
  let program = "f(x) = x + 1\nPrint(f(1))\n" in
  let code, count = hooks program in
  check "no hooks without --debugger" (code = 0 && count = 0);
  let code, count = hooks ~debugger:() program in
  check "hooks with --debugger" (code = 0 && count > 0);
  if !failures > 0 then exit 1;
  print_endline "engine_test: ok"
