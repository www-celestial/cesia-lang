open Types

(* The cases of test.ForAll. A case is the draws its generator made, its tape: replayed, it makes the same value, and a
   shorter or lower tape makes a simpler one, which is how a failure shrinks. Fresh draws come from splitmix64, seeded from
   the run's seed, the file, the test and the rank of the ForAll in it, so that a new test changes no other's cases. *)

type failure = { case : int; cases : int; from : int; until : int; value : t; panic : string option; size : int }

type state = {
  mutable active : bool;  (* under cesia test *)
  mutable seed : int;
  mutable cases : int;
  mutable root : string;
  mutable file : string;  (* from the root *)
  mutable test : string;
  mutable rank : int;  (* the ForAlls of the test so far *)
  mutable rng : int64;
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
}

let st =
  { active = false; seed = 0; cases = 100; root = "."; file = ""; test = ""; rank = 0; rng = 0L; tape = None; pos = 0;
    drawn = Dynarray.create (); size = 0; ran = false; failed = None; on_case = ignore; dir = ""; temp = None; count = 0;
    deadline = infinity; timeout = 10.; clock = (fun () -> 0.) }

(* A test starts: its ForAlls count from 1 again. *)
let start_test ~file ~test =
  st.file <- file;
  st.test <- test;
  st.rank <- 0;
  st.failed <- None;
  st.temp <- None;
  st.count <- st.count + 1;
  st.deadline <- st.clock () +. st.timeout



let fnv s =
  let h = ref 0xcbf29ce484222325L in
  String.iter (fun c -> h := Int64.mul (Int64.logxor !h (Int64.of_int (Char.code c))) 0x100000001b3L) s;
  !h

let next () =
  st.rng <- Int64.add st.rng 0x9E3779B97F4A7C15L;
  let z = st.rng in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27)) 0x94D049BB133111EBL in
  Int64.logxor z (Int64.shift_right_logical z 31)

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
        | None -> Int64.to_int (Int64.unsigned_rem (next ()) (Int64.of_int n))
    in
    st.pos <- st.pos + 1;
    Dynarray.add_last st.drawn v;
    Int v
  | v -> Runtime.fail ctx Type (Messages.need_count "draw" (Value.describe v))

let ints (v : t) =
  match v with
  | Array a -> Some (Array.init (a.rows * a.cols) (fun k -> match Value.elt a k with Int i -> i | _ -> 0))
  | _ -> None

let int_array xs = Array { rows = 1; cols = Array.length xs; store = I xs; a_owned = false; a_tip = true }

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
    match Compile.call_back ctx f args with v -> Ok v | exception Value.Kerr { text; _ } -> Error text
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
  st.rng <- fnv (Printf.sprintf "%d\000%s\000%s\000%d" st.seed st.file st.test st.rank);
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
    Array { rows = 1; cols = Array.length items; store = V items; a_owned = true; a_tip = true }
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
      "defaultCases", nat "defaultCases" 0 0 (fun ctx _ -> only_in_tests ctx; Int st.cases) ];
    "gen",
    [ "draw", nat "draw" 1 1 draw; "size", nat "size" 0 0 (fun _ _ -> Int st.size); "fields", nat "fields" 1 1 fields;
      "make", nat "make" 2 2 make ] ]
