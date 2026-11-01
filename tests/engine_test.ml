(* OCaml tests: the permission mechanism, with natives reserved for tests. *)
open Kepler
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
  Native.register w "read_it" (native "read_it" Read (fun _ _ -> Text "read"));
  Native.register w "read_path"
    (native "read_path" Read (fun ctx a ->
         (match a.(0) with
          | Text p -> Runtime.check_perm ctx Read (Some p)
          | _ -> ());
         Text "read"));
  Native.register w "write_it" (native "write_it" Write (fun _ _ -> Text "written"));
  let path = Filename.temp_file "kepler" ".kp" in
  Out_channel.with_open_bin path (fun oc -> output_string oc src);
  let code = Loader.run w path [] in
  Sys.remove path;
  code, Buffer.contents out, Buffer.contents err

(* How many hooks a program compiled. *)
let hooks ?debugger src =
  let write path text = Out_channel.with_open_bin path (fun oc -> output_string oc text) in
  let path = Filename.temp_file "kepler" ".kp" in
  write path src;
  let dbg = Filename.temp_file "kepler" ".kp" in
  write dbg "on_stop(stop) = \"continue\"\n";
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

let () =
  let code, _, err = run "print(read_it())\n" in
  check "denied by default" (code = 1);
  check "exact denial text" (has "Permission \"read\" denied. Run again with --allow read." err);
  let code, out, _ = run ~perms:[ Read, None ] "print(read_it())\n" in
  check "--allow read" (code = 0 && has "read" out);
  let code, _, err = run ~perms:[ Read, None ] "print(write_it())\n" in
  check "read does not grant write" (code = 1 && has "\"write\"" err);
  let code, _, _ = run ~all:true "print(read_it(), write_it())\n" in
  check "--allow all" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "print(read_path(\"./data/a.txt\"))\n" in
  check "read=./data inside the folder" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "print(read_path(\"./other/a.txt\"))\n" in
  check "read=./data outside the folder" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "print(read_path(\"./data/../secret.txt\"))\n" in
  check "escape through .. denied" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "print(read_path(\"./data\"))\n" in
  check "read=./data covers the folder itself" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "./data" ] "print(read_path(\"./database/a.txt\"))\n" in
  check "read=./data does not cover ./database" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "print(read_path(\"/etc/passwd\"))\n" in
  check "read=. does not cover an absolute path" (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "print(read_path(\"../secret.txt\"))\n" in
  check "read=. does not cover .." (code = 1);
  let code, _, _ = run ~perms:[ Read, Some "." ] "print(read_path(\"./a/b.txt\"))\n" in
  check "read=. covers its subfolders" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "/" ] "print(read_path(\"/etc/hosts\"))\n" in
  check "read=/ covers every absolute path" (code = 0);
  let code, _, _ = run ~perms:[ Read, Some "/tmp" ] "print(read_path(\"/tmp/../etc/passwd\"))\n" in
  check "read=/tmp denies escape through .." (code = 1);
  let code, _, _ = run "f = read_it\nprint(f())\n" in
  check "also denied through a dynamic call" (code = 1);
  let code, _, _ = run "print(map(read_it, [1]))\n" in
  check "also denied from the prelude" (code = 1);
  check "exec is exact" (Runtime.scope_matches Exec "git" "git" && not (Runtime.scope_matches Exec "git" "git2"));
  check "env is exact" (Runtime.scope_matches Env "HOME" "HOME" && not (Runtime.scope_matches Env "HOME" "PATH"));
  check "net port" (Runtime.scope_matches Net ":8080" ":8080" && not (Runtime.scope_matches Net ":8080" ":8081"));
  check "net host" (Runtime.scope_matches Net "a.com" "a.com:443" && not (Runtime.scope_matches Net "a.com" "b.com:443"));
  check "net host and port"
    (Runtime.scope_matches Net "a.com:443" "a.com:443" && not (Runtime.scope_matches Net "a.com:443" "a.com:80"));
  check "net host is no suffix" (not (Runtime.scope_matches Net "a.com" "evil-a.com:443"));
  check "read stays a path" (Runtime.scope_matches Read "./data" "./data/a" && not (Runtime.scope_matches Read "./data" "./b"));
  check "default memory is 80% of MemTotal"
    (Runtime.default_memory "MemFree: 1 kB\nMemTotal:     1000 kB\n" = 102_400);
  check "unknown RAM means no limit" (Runtime.default_memory "" = max_int);
  let program = "f(x) = x + 1\nprint(f(1))\n" in
  let code, count = hooks program in
  check "no hooks without --debugger" (code = 0 && count = 0);
  let code, count = hooks ~debugger:() program in
  check "hooks with --debugger" (code = 0 && count > 0);
  if !failures > 0 then exit 1;
  print_endline "engine_test: ok"
