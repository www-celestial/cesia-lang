open Types

(* The cases of test.ForAll. A case is the draws its generator made, its tape: replayed, it makes the same value, and a
   shorter or lower tape makes a simpler one, which is how a failure shrinks. Fresh draws come from std/random's generator,
   which each test starts from the seed of the run and its own name, so that a new test changes no other's cases. *)

type failure = { case : int; cases : int; from : int; until : int; value : t; panic : string option; size : int }

type state = {
  mutable active : bool;  (* under cesia test *)
  mutable cases : int;
  mutable root : string;
  mutable file : string;  (* from the root *)
  mutable test : string;
  mutable rank : int;  (* the ForAlls of the test so far *)
  mutable tape : int array option;  (* the tape replayed, or fresh draws *)
  mutable pos : int;
  drawn : int Dynarray.t;
  mutable size : int;
  mutable ran : bool;  (* some property ran in this run *)
  mutable failed : failure option;  (* of the test running *)
  mutable on_case : unit -> unit;  (* a property starts: what its verdict noted before is gone *)
  mutable dir : string;  (* the run's folder, which holds the Temp folder of each test *)
  mutable temp : string option;  (* the Temp folder of the test running, once asked *)
  mutable count : int;  (* the tests so far *)
  mutable deadline : float;
  mutable timeout : float;
  mutable clock : unit -> float;
  mutable path : string;  (* the file of the test running, as given *)
  mutable update : bool;  (* cesia test --update: snapshots are written, not compared *)
  mutable snaps : int;  (* the snapshots of the test so far *)
  mutable store : (string * (string * int, string) Hashtbl.t) option;  (* the .snap of the file, read at its first snapshot *)
  taken : (string * int, string) Hashtbl.t;  (* the snapshots this run took, for --update *)
  mutable snap_failure : string list;  (* what the failed snapshot of the test shows *)
}

let st =
  { active = false; cases = 100; root = "."; file = ""; test = ""; rank = 0; tape = None; pos = 0;
    drawn = Dynarray.create (); size = 0; ran = false; failed = None; on_case = ignore; dir = ""; temp = None; count = 0;
    deadline = infinity; timeout = 10.; clock = (fun () -> 0.); path = ""; update = false; snaps = 0; store = None;
    taken = Hashtbl.create 8; snap_failure = [] }

let fnv s =
  let h = ref 0xcbf29ce484222325L in
  String.iter (fun c -> h := Int64.mul (Int64.logxor !h (Int64.of_int (Char.code c))) 0x100000001b3L) s;
  !h

(* A test starts: its ForAlls count from 1 again. *)
let start_test ~path ~file ~test =
  st.path <- path;
  st.file <- file;
  st.test <- test;
  st.rank <- 0;
  st.failed <- None;
  st.temp <- None;
  st.snaps <- 0;
  st.snap_failure <- [];
  st.count <- st.count + 1;
  st.deadline <- st.clock () +. st.timeout;
  (* The numbers of a test, std/random's and its cases', come from the seed of the run and its name alone. *)
  Rand.restart (Int64.to_int (fnv (Printf.sprintf "%d\000%s\000%s" (Rand.seed ()) file test)))




(* Past this many draws a case draws 0, which ends any generator that stops at 0. *)
let most_draws = 100_000

let draw ctx (a : t array) =
  match a.(0) with
  | Int n when n > 0 ->
    let v =
      if Dynarray.length st.drawn >= most_draws then 0
      else
        match st.tape with
        | Some t -> if st.pos < Array.length t then (let x = t.(st.pos) in if x < 0 then 0 else if x < n then x else x mod n) else 0
        | None -> Rand.below n
    in
    st.pos <- st.pos + 1;
    Dynarray.add_last st.drawn v;
    Int v
  | v -> Runtime.fail ctx Type (Messages.need_count "draw" (Value.describe v))

let ints (v : t) =
  match v with
  | Array a -> Some (Array.init (a.rows * a.cols) (fun k -> match Value.elt a k with Int i -> i | _ -> 0))
  | _ -> None

let int_array xs = Array { rows = 1; cols = Array.length xs; store = I xs; a_owned = false; a_tip = true; dims = [||] }

let only_in_tests ctx = if not st.active then Runtime.fail ctx User Messages.test_only

(* temp(): the Temp folder of the test, made at its first call. *)
let temp ctx _ =
  only_in_tests ctx;
  match st.temp with
  | Some d -> Text d
  | None ->
    let d = Filename.concat st.dir (Printf.sprintf "%d-%s" st.count st.test) in
    (try
       if not (Sys.file_exists st.dir) then Sys.mkdir st.dir 0o700;
       Sys.mkdir d 0o700
     with Sys_error m -> Runtime.fail ctx User (Messages.plain m));
    st.temp <- Some d;
    Text d

(* A .snap file: blocks of "== isName N (L lines)" and the L lines of the text, ", no line end" when it has none. *)
let snap_path path = Filename.remove_extension path ^ ".snap"

let lines_of text =
  let ls = String.split_on_char '\n' text in
  if String.ends_with ~suffix:"\n" text then List.rev (List.tl (List.rev ls)) else ls

let read_snaps path =
  let table = Hashtbl.create 8 in
  (match In_channel.with_open_bin (snap_path path) In_channel.input_all with
   | exception Sys_error _ -> ()
   | src ->
     let rec go = function
       | head :: rest when String.starts_with ~prefix:"== " head ->
         (match String.split_on_char ' ' head with
          | "==" :: name :: k :: l :: more when String.starts_with ~prefix:"(" l && List.length more >= 1 ->
            let ending = if List.mem "end)" more then "no line end" else "" in
            (match int_of_string_opt k, int_of_string_opt (String.sub l 1 (String.length l - 1)) with
             | Some k, Some l when l >= 0 && List.length rest >= l ->
            let body = List.filteri (fun i _ -> i < l) rest in
            Hashtbl.replace table (name, k) (String.concat "\n" body ^ if ending = "" then "\n" else "");
            go (List.filteri (fun i _ -> i >= l) rest)
             | _ -> go rest)
          | _ -> go rest)
       | _ :: rest -> go rest
       | [] -> ()
     in
     go (String.split_on_char '\n' src));
  table

let block (name, k) text =
  let ls = lines_of text in
  Printf.sprintf "== %s %d (%d lines%s)\n%s" name k (List.length ls) (if String.ends_with ~suffix:"\n" text then "" else ", no line end")
    (String.concat "" (List.map (fun l -> l ^ "\n") ls))

(* The lines that changed, the common head and tail cut, 20 at most. *)
let changed old now =
  let a = Array.of_list (lines_of old) and b = Array.of_list (lines_of now) in
  let head = ref 0 in
  while !head < Array.length a && !head < Array.length b && a.(!head) = b.(!head) do incr head done;
  let tail = ref 0 in
  while !tail < Array.length a - !head && !tail < Array.length b - !head && a.(Array.length a - 1 - !tail) = b.(Array.length b - 1 - !tail) do incr tail done;
  let part x sign = List.init (Array.length x - !head - !tail) (fun i -> sign ^ x.(!head + i)) in
  let lines = part a "- " @ part b "+ " in
  Printf.sprintf "@@ from line %d" (!head + 1) :: List.filteri (fun i _ -> i < 20) lines

(* snapshot(text): is it the text kept for this snapshot of the test? With --update it is kept, and is. *)
let snapshot ctx (a : t array) =
  only_in_tests ctx;
  let text = match a.(0) with Text t -> t | v -> Value.text_of ctx v in
  st.snaps <- st.snaps + 1;
  let key = st.test, st.snaps in
  Hashtbl.replace st.taken key text;
  let store =
    match st.store with
    | Some (p, t) when String.equal p st.path -> t
    | _ -> let t = read_snaps st.path in st.store <- Some (st.path, t); t
  in
  if st.update then True
  else
    match Hashtbl.find_opt store key with
    | Some kept when String.equal kept text -> True
    | Some kept -> st.snap_failure <- Messages.snapshot_changed st.snaps :: changed kept text; False
    | None -> st.snap_failure <- Messages.snapshot_new st.snaps :: List.filteri (fun i _ -> i < 20) (lines_of text); False

(** With --update, writes the .snap of a file: the snapshots of the tests that ran, the others' kept unless their test is gone. *)
let write_snaps path ~ran ~tests =
  if st.update then begin
    let kept = read_snaps path in
    let all = Hashtbl.create 16 in
    Hashtbl.iter (fun (n, k) t -> if List.mem n tests && not (List.mem n ran) then Hashtbl.replace all (n, k) t) kept;
    Hashtbl.iter (fun key t -> Hashtbl.replace all key t) st.taken;
    let keys = List.sort compare (Hashtbl.fold (fun key _ acc -> key :: acc) all []) in
    let target = snap_path path in
    if keys = [] then (try Sys.remove target with Sys_error _ -> ())
    else begin
      let tmp = target ^ ".new" in
      Out_channel.with_open_bin tmp (fun oc -> List.iter (fun key -> output_string oc (block key (Hashtbl.find all key))) keys);
      Sys.rename tmp target
    end
  end;
  Hashtbl.reset st.taken;
  st.store <- None

let case_keys = Trie.names [| "Value"; "Tape"; "Size"; "Holds"; "Panic" |]

(* oneCase(g, prop, tape, size): a value from g, replaying the tape if it isn't missing, and whether prop holds for it. A panic
   in either is a failed case, with its message. *)
let one_case ctx (a : t array) =
  only_in_tests ctx;
  st.tape <- ints a.(2);
  st.size <- (match a.(3) with Int s -> s | _ -> 100);
  st.pos <- 0;
  Dynarray.clear st.drawn;
  (* Each call goes above the frame of the caller of oneCase: the site of that call places it, so it is set again. *)
  let site = ctx.site in
  let call f args =
    ctx.site <- site;
    match Loader.call_caught ctx f args with
    | Ok v -> Ok v
    | Error (Value.Kerr { text; _ }) -> Error text
    | Error (Value.Quit code) -> Error (Messages.test_exit code)
    | Error e -> raise e
  in
  let value, holds, panic =
    match call a.(0) [||] with
    | Error m -> Missing, false, Some m
    | Ok x ->
      st.on_case ();
      (match call a.(1) [| x |] with Ok True -> x, true, None | Ok _ -> x, false, None | Error m -> x, false, Some m)
  in
  ctx.site <- site;
  let tape = int_array (Dynarray.to_array st.drawn) in
  Trie.record case_keys [| Value.share value; tape; Int st.size; Value.of_bool holds; (match panic with Some m -> Text m | None -> Missing) |]

(* The failure saved for the ForAll running, as a file of .cesia/failures/ at the root: its size, then its draws. *)
let saved_path () =
  let name = String.map (function '/' | '\\' | ':' -> '-' | c -> c) (Printf.sprintf "%s-%s-%d" st.file st.test st.rank) in
  Filename.concat (Filename.concat (Filename.concat st.root ".cesia") "failures") name

let saved () =
  match In_channel.with_open_bin (saved_path ()) In_channel.input_all with
  | exception Sys_error _ -> None
  | text ->
    match List.map int_of_string_opt (String.split_on_char ' ' (String.trim text)) with
    | Some size :: draws when List.for_all Option.is_some draws -> Some (size, Array.of_list (List.map Option.get draws))
    | _ -> None

let start ctx _ =
  only_in_tests ctx;
  st.rank <- st.rank + 1;
  st.ran <- true;
  match saved () with
  | Some (size, draws) -> Trie.record (Trie.names [| "Size"; "Tape" |]) [| Int size; int_array draws |]
  | None -> Missing

let mkdir d = if not (Sys.file_exists d) then Sys.mkdir d 0o755

let save ctx (a : t array) =
  only_in_tests ctx;
  let path = saved_path () in
  (try
     mkdir (Filename.dirname (Filename.dirname path));
     mkdir (Filename.dirname path);
     let draws = Option.value (ints a.(1)) ~default:[||] in
     Out_channel.with_open_bin path (fun oc ->
         output_string oc (String.concat " " (List.map string_of_int ((match a.(0) with Int s -> s | _ -> 100) :: Array.to_list draws)));
         output_char oc '\n')
   with Sys_error _ -> ());
  Missing

let drop ctx _ =
  only_in_tests ctx;
  (try Sys.remove (saved_path ()) with Sys_error _ -> ());
  Missing

(* failed({Case, Cases, From, To, Value, Panic, Size}): what the runner shows of the failure. *)
let failed ctx (a : t array) =
  only_in_tests ctx;
  let get name = match Dict.get ctx "failed" (Text name) a.(0) with Some v -> v | None -> Missing in
  let int name = match get name with Int i -> i | _ -> 0 in
  st.failed <-
    Some { case = int "Case"; cases = int "Cases"; from = int "From"; until = int "To"; value = get "Value"; size = int "Size";
           panic = (match get "Panic" with Text m -> Some m | _ -> None) };
  Missing

let field_keys = Trie.names [| "Name"; "Type"; "Optional" |]

(* fields(S): the fields of a struct, each with the kind or the struct its type names, or missing when it has none. *)
let fields ctx (a : t array) =
  match a.(0) with
  | Fun { proto; _ } when Resolve.struct_fields proto.func <> None ->
    let ty (p : Ast.param) =
      match p.ptype with
      | None -> Missing
      | Some { tb = Ast.Cell { m; k; _ }; _ } when m < Array.length ctx.w.modules -> ctx.w.modules.(m).cells.(k)
      | Some t -> Text t.tname
    in
    let items =
      Array.map (fun (p : Ast.param) ->
          Trie.record field_keys [| Text p.pname; ty p; Value.of_bool (match p.ptype with Some t -> t.topt | None -> false) |])
        proto.func.params
    in
    Array { rows = 1; cols = Array.length items; store = V items; a_owned = true; a_tip = true; dims = [||] }
  | v -> Runtime.fail ctx Type (Messages.need_struct "gen.Of" (Value.describe v))

let make ctx (a : t array) =
  match a.(1) with
  | Array v -> Compile.call_back ctx a.(0) (Array.init (v.rows * v.cols) (Value.elt v))
  | v -> Runtime.fail ctx Type (Messages.need_struct "gen.Of" (Value.describe v))

let nat = Native.nat

(** The natives of std/test and of std/gen, all private: their Cesia parts give the names to use. *)
let natives =
  [ "test",
    [ "start", nat "start" 0 0 start; "oneCase", nat "oneCase" 4 4 one_case; "save", nat "save" 2 2 save;
      "drop", nat "drop" 0 0 drop; "failed", nat "failed" 1 1 failed; "temp", nat "temp" 0 0 temp;
      "snapshot", nat "snapshot" 1 1 snapshot;
      "defaultCases", nat "defaultCases" 0 0 (fun ctx _ -> only_in_tests ctx; Int st.cases) ];
    "gen",
    [ "draw", nat "draw" 1 1 draw; "size", nat "size" 0 0 (fun _ _ -> Int st.size); "fields", nat "fields" 1 1 fields;
      "make", nat "make" 2 2 make ] ]
