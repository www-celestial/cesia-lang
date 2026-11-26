(* Name resolution blocks in libc: a slow answer must stop only the fiber that asked. *)
open Cesia

(* How many lines "tick" the program printed, which a slow resolution waits for on its own domain. *)
let ticks = Atomic.make 0

(* A port of this machine that the system gave free, closed again: one written here could be held by a server of a suite
   that runs beside. *)
let free_port () =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind s (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port = match Unix.getsockname s with Unix.ADDR_INET (_, p) -> p | _ -> 0 in
  Unix.close s;
  port

(* A program, with the uses of the packages that these name at its end, so that its lines stay as written. *)
let run ?(grants = { Types.all = true; perms = [] }) source =
  let path = Filename.temp_file "net_test" ".ce" in
  let file = open_out path in
  let has text =
    let n = String.length source and m = String.length text in
    let rec go i = i + m <= n && (String.sub source i m = text || go (i + 1)) in
    go 0
  in
  let packages = [ "io"; "fiber"; "net"; "list"; "text"; "result"; "sys"; "value" ] in
  output_string file (source ^ String.concat "" (List.map (fun p -> if has ("use std/" ^ p) then "" else "\nuse std/" ^ p) packages) ^ "\n");
  close_out file;
  let out = Buffer.create 64 and err = Buffer.create 64 in
  let print text =
    Buffer.add_string out text;
    if String.length text >= 4 && String.sub text 0 4 = "tick" then Atomic.incr ticks
  in
  let options =
    { Runtime.default_options with
      o_grants = grants;
      o_sink = print;
      o_err = Buffer.add_string err }
  in
  let w = Runtime.create_world options in
  let (_ : unit -> bool) = Cesia_sys.Sys_modules.register w in
  let code = Loader.run_file ~strict:true w path [] in
  Sys.remove path;
  code, Buffer.contents out, Buffer.contents err

(* What a fiber did: "ok", "err" for an Err it gave, or the kind of its panic, as "permission". *)
let kind =
  {|
defn kind(f)
  match fiber.Wait(fiber.Spawn(f))
    result.Ok(r) -> if result.IsErr(r) "err" else "ok" end
    result.Err(e) -> e.Kind
  end
end
|}

(* What the program printed, and nothing on its errors but with [~panics], where a denied permission tells its place. *)
let check ?(panics = false) name want (code, got, errors) =
  if code <> 0 || got <> want || (errors <> "" && not panics) then begin
    Printf.printf "%s: exit %d, expected:\n%s\ngot:\n%s%s\n" name code want got errors;
    exit 1
  end

let () =
  let slow answer host =
    Unix.sleepf 0.03;
    answer host
  in
  (* The answer comes only once the other fiber printed twice, so the order holds on a slow machine; were the fibers stopped, it would come after 10 s, last. *)
  let after_ticks answer host =
    let deadline = Unix.gettimeofday () +. 10. in
    while Atomic.get ticks < 2 && Unix.gettimeofday () < deadline do
      Unix.sleepf 0.001
    done;
    answer host
  in
  Atomic.set ticks 0;
  Cesia_sys.Net.resolver := after_ticks (fun _ -> Unix.inet_addr_loopback);
  check "a fiber runs during a slow resolution" "tick\ntick\ndone\n"
    (run
       {|use std/sys
use std/net
defn ticks()
  sys.Sleep(0.005)
  io.Print("tick")
  sys.Sleep(0.005)
  io.Print("tick")
end
t = fiber.Spawn(ticks)
r = net.Connect("slow.example", 1)
io.Print("done")
fiber.Wait(t)
|});
  Cesia_sys.Net.resolver := slow (fun _ -> raise Not_found);
  check "an unknown name is an error" "unknown\n"
    (run
       {|use std/net
io.Print(match net.Connect("nowhere.example", 1)
  result.Err(e) -> if text.Contains("unknown host", e.Message) "unknown" else e.Message end
  result.Ok(s) -> "connected"
end)
|});
  Cesia_sys.Net.resolver := slow (fun _ -> Unix.inet_addr_loopback);
  check "several fibers wait at once" "2\n"
    (run
       {|use std/net
tasks = list.Map(h -> fiber.Spawn(() -> net.Connect(h, 1)), ["a.example", "b.example"])
io.Print(value.Len(list.Map(fiber.Wait, tasks)))
|});
  Cesia_sys.Net.resolver := (fun _ -> failwith "no lookup for an address");
  check "an address needs no lookup" "done\n"
    (run
       {|use std/net
r = net.Connect("127.0.0.1", 1)
io.Print("done")
|});
  (* The domain still sleeps when the program ends: the test only finishes if nothing waits for it. *)
  Cesia_sys.Net.resolver := (fun _ -> Unix.sleepf 30.; Unix.inet_addr_loopback);
  check "a program doesn't wait for a lookup" "end\n"
    (run
       {|use std/sys
use std/net
t = fiber.Spawn(() -> net.Connect("a.example", 1))
sys.Sleep(0.005)
io.Print("end")
|});
  (* The loopback check is on the address a name resolves to, not on its text, and the address checked is the one bound. *)
  let net scopes = { Types.all = false; perms = List.map (fun s -> Types.Net, Some s) scopes } in
  let names = Atomic.make [] in
  let resolve table host =
    Atomic.set names (host :: Atomic.get names);
    match List.assoc_opt host table with
    | Some a -> Unix.inet_addr_of_string a
    | None -> raise Not_found
  in
  Cesia_sys.Net.resolver := resolve [ "127.x.wide.example", "0.0.0.0"; "near.example", "127.0.0.1" ];
  let port = free_port () in
  check ~panics:true "net=:PORT listens on the address a name resolves to only when it is of this machine" "permission\nok\n"
    (run ~grants:(net [ Printf.sprintf ":%d" port ])
       (kind ^ Printf.sprintf {|io.Print(kind(() -> net.Listen(%d, host = "127.x.wide.example")))
io.Print(kind(() -> net.Listen(%d, host = "near.example")))
|} port port));
  Atomic.set names [];
  check ~panics:true "net=own looks up no name, and reaches its own listeners only while they are open"
    "permission\npermission\nok\nok\npermission\n"
    (run ~grants:(net [ "own" ])
       (kind ^ {|io.Print(kind(() -> net.Connect("127.x.leak.example", 80)))
io.Print(kind(() -> net.Listen(0, host = "127.x.leak.example")))
l = result.Unwrap(net.Listen(0))
p = net.Port(l)
io.Print(kind(() -> net.Connect("127.0.0.1", p)))
io.Print(kind(() -> net.Connect("localhost", p)))
net.Close(l)
io.Print(kind(() -> net.Connect("127.0.0.1", p)))
|}));
  if Atomic.get names <> [] then begin
    Printf.printf "net=own looked up %s\n" (String.concat ", " (Atomic.get names));
    exit 1
  end;
  let port = free_port () in
  check "net=own reaches its own listener on every address through 127.0.0.1" "ok\n"
    (run ~grants:(net [ "own"; Printf.sprintf "0.0.0.0:%d" port ])
       (kind ^ Printf.sprintf {|l = result.Unwrap(net.Listen(%d, host = "0.0.0.0"))
io.Print(kind(() -> net.Connect("127.0.0.1", %d)))
|} port port));
  if Cesia_sys.Sys_modules.ram () < 1_000_000 then failwith "the RAM of the machine isn't known";
  print_endline "net_test: ok"
