(* Name resolution blocks in libc: a slow answer must stop only the fiber that asked. *)
open Cesia

let run source =
  let path = Filename.temp_file "net_test" ".ce" in
  let file = open_out path in
  output_string file source;
  close_out file;
  let out = Buffer.create 64 in
  let options =
    { Runtime.default_options with
      o_grants = { all = true; perms = [] };
      o_sink = Buffer.add_string out;
      o_err = Buffer.add_string out }
  in
  let w = Runtime.create_world options in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  let code = Loader.run_file ~strict:true w path [] in
  Sys.remove path;
  code, Buffer.contents out

let check name want (code, got) =
  if code <> 0 || got <> want then begin
    Printf.printf "%s: exit %d, expected:\n%s\ngot:\n%s\n" name code want got;
    exit 1
  end

let () =
  let slow answer host =
    Unix.sleepf 0.03;
    answer host
  in
  Cesia_sys.Net.resolver := slow (fun _ -> Unix.inet_addr_loopback);
  check "a fiber runs during a slow resolution" "tick\ntick\ndone\n"
    (run
       {|use sys
use net
defn ticks()
  sys.Sleep(0.005)
  Print("tick")
  sys.Sleep(0.005)
  Print("tick")
end
t = Spawn(ticks)
r = net.Connect("slow.example", 1)
Print("done")
Wait(t)
|});
  Cesia_sys.Net.resolver := slow (fun _ -> raise Not_found);
  check "an unknown name is an error" "unknown\n"
    (run
       {|use net
Print(match net.Connect("nowhere.example", 1)
  Err(e) -> if Contains("unknown host", e.Message) "unknown" else e.Message end
  Ok(s) -> "connected"
end)
|});
  Cesia_sys.Net.resolver := slow (fun _ -> Unix.inet_addr_loopback);
  check "several fibers wait at once" "2\n"
    (run
       {|use net
tasks = Map(h -> Spawn(() -> net.Connect(h, 1)), ["a.example", "b.example"])
Print(Len(Map(Wait, tasks)))
|});
  Cesia_sys.Net.resolver := (fun _ -> failwith "no lookup for an address");
  check "an address needs no lookup" "done\n"
    (run
       {|use net
r = net.Connect("127.0.0.1", 1)
Print("done")
|});
  (* The domain still sleeps when the program ends: the test only finishes if nothing waits for it. *)
  Cesia_sys.Net.resolver := (fun _ -> Unix.sleepf 30.; Unix.inet_addr_loopback);
  check "a program doesn't wait for a lookup" "end\n"
    (run
       {|use sys
use net
t = Spawn(() -> net.Connect("a.example", 1))
sys.Sleep(0.005)
Print("end")
|});
  if Cesia_sys.Sys_modules.ram () < 1_000_000 then failwith "the RAM of the machine isn't known";
  print_endline "net_test: ok"
