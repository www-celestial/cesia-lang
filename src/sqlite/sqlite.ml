open Cesia
open Types

external call : int -> int -> Bytes.t -> string array -> int -> unit = "cesia_call" [@@noalloc]
external dlopen : string -> int = "cesia_dlopen"
external dlsym : int -> string -> int = "cesia_dlsym"
external dlerror : unit -> string = "cesia_dlerror"
external cstring : int -> string = "cesia_cstring"
external bytes : int -> int -> string = "cesia_bytes"
external db_config : int -> int -> int -> int -> int = "cesia_db_config"
external strdup : string -> int = "cesia_strdup"
external free : int -> unit = "cesia_free"
external peek : int -> int -> int64 = "cesia_peek"

(* The functions of the library, found once. *)
type lib = {
  open_v2 : int; close_v2 : int; prepare : int; finalize : int; reset : int; clear : int; step : int;
  count : int; bind_null : int; bind_int : int; bind_float : int; bind_text : int; columns : int; name : int;
  decltype : int; kind : int; get_int : int; get_float : int; get_text : int; get_blob : int; size : int;
  changes : int; last_id : int; errmsg : int; errcode : int; config : int; limit : int; version : int;
  autocommit : int; exec : int; status : int;
}

(* A statement and what it says of its columns, read once. *)
type prepared = {
  stmt : int;
  ptext : string;
  extra : bool;  (** made while the cached one of its text was in use: finalized when it comes back *)
  mutable inuse : bool;
  mutable reprepared : int;  (** how many times SQLite prepared it again, after a change of the schema *)
  mutable names : t;
  mutable texts : string array;
  mutable bools : bool array;  (** the columns declared BOOLEAN *)
  mutable keys : (keys, string) result option;  (** of its rows, the names made public names *)
}

type conn = {
  id : int;
  db : int;
  mutable wait : float;  (** how long a busy database is waited for, in the calls that run a whole statement *)
  cache : (string, prepared) Hashtbl.t;  (** a statement by text: one in use is never handed out twice *)
  mutable last : prepared option;  (** the last one handed out, found again by the text itself, without a hash *)
  mutable broken : bool;
  mutable closed : bool;
  live : (int, unit) Hashtbl.t;  (** its cursors *)
}

type cursor = { p : prepared; text : string; owner : conn; mutable rows : int }

(* Connections opened when needed, at most [size], and the fibers waiting for one. *)
type pool = {
  path : string;
  size : int;
  pool_wait : float;
  mutable free : conn list;
  mutable opened : int;
  mutable shut : bool;
  mutable waiters : (unit -> unit) list;
}

let library = ref None
let pools : (int, pool) Hashtbl.t = Hashtbl.create 4
let conns : (int, conn) Hashtbl.t = Hashtbl.create 4
let cursors : (int, cursor) Hashtbl.t = Hashtbl.create 16
let next_id = ref 1

(* Six words of arguments, then the result, as cesia_call reads them; [scratch] holds two out pointers. *)
let slots = Bytes.make 56 '\000'
let texts = Array.make 6 ""
let scratch = lazy (strdup (String.make 15 ' '))
let set k x = Bytes.set_int64_ne slots (k * 8) (Int64.of_int x)
let result () = Bytes.get_int64_ne slots 48
let ints n = ((1 lsl n) - 1) * 2

let run f n ?(text = -1) () =
  call f (ints n) slots texts (if text < 0 then 0 else 1 lsl text);
  Int64.to_int (result ())

let c1 f a = set 0 a; run f 1 ()
let c2 f a b = set 0 a; set 1 b; run f 2 ()
let c3 f a b c = set 0 a; set 1 b; set 2 c; run f 3 ()

let codes = [ 1555, "23505"; 2067, "23505"; 787, "23503"; 1299, "23502"; 275, "23514" ]
let error_keys = Trie.names [| "Kind"; "Code"; "Message" |]
let failure ctx code message =
  Value.err ctx.w (Trie.record error_keys [| Text "sql"; Text code; Text message |])

let sqlite_code rc = match List.assoc_opt rc codes with Some c -> c | None -> Printf.sprintf "sqlite-%d" rc

(* The error of the last call on [c]: an I/O error or a damaged file leave the connection broken. *)
let last_error ctx lib c =
  let rc = c1 lib.errcode c.db in
  if List.mem (rc land 0xFF) [ 10; 11; 14; 21; 26 ] then c.broken <- true;
  failure ctx (sqlite_code rc) (cstring (c1 lib.errmsg c.db))

let load ctx =
  (* No ffi permission: this module reaches no file a read= and write= don't grant, and loads no extension; c.Open, which
     would trust the library with everything, refuses SQLite's. *)
  match !library with
  | Some lib -> Ok lib
  | None ->
    let try_file (found, reason) path =
      if found <> 0 then found, reason
      else
        let h = dlopen path in
        h, if h = 0 && reason = "" then dlerror () else reason
    in
    (match List.fold_left try_file (0, "") (Cesia_sys.C.candidates "sqlite3" (Some "0")) with
     | 0, reason -> Error (Messages.c_no_library "sqlite3" reason).text
     | h, _ ->
       let f name = dlsym h ("sqlite3_" ^ name) in
       let lib =
         { open_v2 = f "open_v2"; close_v2 = f "close_v2"; prepare = f "prepare_v2"; finalize = f "finalize";
           reset = f "reset"; clear = f "clear_bindings"; step = f "step"; count = f "bind_parameter_count";
           bind_null = f "bind_null"; bind_int = f "bind_int64"; bind_float = f "bind_double"; bind_text = f "bind_text";
           columns = f "column_count"; name = f "column_name"; decltype = f "column_decltype"; kind = f "column_type";
           get_int = f "column_int64"; get_float = f "column_double"; get_text = f "column_text";
           get_blob = f "column_blob"; size = f "column_bytes"; changes = f "changes64"; last_id = f "last_insert_rowid";
           errmsg = f "errmsg"; errcode = f "extended_errcode"; config = f "db_config"; limit = f "limit";
           version = f "libversion"; autocommit = f "get_autocommit"; exec = f "exec";
           status = f "stmt_status" }
       in
       library := Some lib;
       Ok lib)

let with_lib ctx f = match load ctx with Ok lib -> f lib | Error text -> failure ctx "library" text
let handle kind id = Handle { kind; id; task = None }

let new_id () =
  let id = !next_id in
  incr next_id;
  id

let zero_free ctx what s = if String.contains s '\000' then Runtime.fail ctx Type (Messages.sql_zero_byte what)

(* Read-write, created if absent, no URI names, extended codes; then defensive, no trusted schema, no extension, no
   double-quoted texts, texts and BLOBs of 100 MB at most, nothing attached, and no busy wait: this module waits in the
   fiber, so the other fibers run meanwhile. *)
let path_arg ctx name v =
  let path = Native.text_arg ctx name v in
  zero_free ctx "a path" path;
  (* A SQLite built to read URIs would take file:/etc/x.db?vfs=... past the check of the path. *)
  if String.length path >= 5 && String.lowercase_ascii (String.sub path 0 5) = "file:" then
    Runtime.fail ctx Type (Messages.sql_uri path);
  (* SQLite writes beside the database too: its journal, or in WAL mode the files -wal and -shm. *)
  if path <> ":memory:" then
    List.iter
      (fun p ->
        Runtime.check_perm ctx Read (Some p);
        Runtime.check_perm ctx Write (Some p))
      [ path; path ^ "-wal"; path ^ "-shm"; path ^ "-journal" ];
  path

let open_conn ctx lib path =
  let out = Lazy.force scratch in
  texts.(0) <- path;
  set 1 out; set 2 (0x2 lor 0x4 lor 0x8000 lor 0x02000000); set 3 0;
  let rc = run lib.open_v2 4 ~text:0 () and db = Int64.to_int (peek out 8) in
  let c =
    { id = new_id (); db; wait = 5.; cache = Hashtbl.create 16; last = None; broken = false; closed = false;
      live = Hashtbl.create 4 }
  in
  if rc <> 0 then begin
    let e = if db = 0 then failure ctx (sqlite_code rc) "out of memory" else last_error ctx lib c in
    if db <> 0 then ignore (c1 lib.close_v2 db);
    Error e
  end
  else begin
    List.iter (fun (op, on) -> ignore (db_config lib.config db op on)) [ 1010, 1; 1017, 0; 1005, 0; 1013, 0; 1014, 0 ];
    ignore (c3 lib.limit db 0 100_000_000);
    ignore (c3 lib.limit db 7 0);
    Hashtbl.replace conns c.id c;
    Ok c
  end

let conn_arg ctx name (v : t) =
  match v with
  | Handle { kind = "connection"; id; _ } -> (match Hashtbl.find_opt conns id with Some c when not c.closed -> Some c | _ -> None)
  | _ -> Runtime.fail ctx Type (Messages.sql_need_handle name "connection" (Value.describe v))

let closed ctx = failure ctx "closed" (Messages.sql_closed).text
let finalize lib stmt = ignore (c1 lib.finalize stmt)

(* A statement given back, reset: free again in the cache. A closed connection has finalized those of its cache, and a
   broken one finalizes it. Its bindings stay until the next call binds every value again. *)
let give_back lib c (_ : string) p =
  if not c.closed then ignore (c1 lib.reset p.stmt);
  p.inuse <- false;
  if p.extra || (c.broken && not c.closed) then begin
    if not c.closed || p.extra then finalize lib p.stmt;
    if not p.extra then Hashtbl.remove c.cache p.ptext;
    match c.last with Some q when q == p -> c.last <- None | _ -> ()
  end

(* [prepare lib c text]: a statement and the text that follows it. *)
let prepare lib c text =
  let out = Lazy.force scratch and z = strdup text in
  set 0 c.db; set 1 z; set 2 (String.length text); set 3 out; set 4 (out + 8);
  let rc = run lib.prepare 5 () in
  let stmt = Int64.to_int (peek out 8) and tail = Int64.to_int (peek (out + 8) 8) - z in
  free z;
  rc, stmt, if rc = 0 then String.sub text tail (String.length text - tail) else ""

let decltypes lib stmt n =
  Array.init n (fun k ->
      let p = c2 lib.decltype stmt k in
      p <> 0 && String.uppercase_ascii (cstring p) = "BOOLEAN")

(* A system's SQLite may keep the pragmas temp_store_directory and data_store_directory, which would move its files past
   the check of the path. *)
let no_directory ctx text = if Native.find_from ~fold:true text "store_directory" 0 >= 0 then Runtime.fail ctx Type Messages.sql_store_directory

(* One statement: text after it that holds another is an error, so none rides in on a value glued by hand. *)
let statement ctx lib c text =
  let hand p = p.inuse <- true; Ok p in
  match c.last with
  | Some p when p.ptext == text && not p.inuse -> hand p
  | _ ->
  match Hashtbl.find_opt c.cache text with
  | Some p when not p.inuse -> c.last <- Some p; hand p
  | found ->
    no_directory ctx text;
    let rc, stmt, rest = if String.contains text '\000' then -1, 0, "" else prepare lib c text in
    if rc < 0 then Error (failure ctx "statements" (Messages.sql_zero_byte "a statement").text)
    else if rc <> 0 then Error (last_error ctx lib c)
    else if stmt = 0 then Error (failure ctx "statements" (Messages.sql_no_statement).text)
    else
      match prepare lib c rest with
      | 0, 0, _ ->
        let n = c1 lib.columns stmt in
        let texts = Array.init n (fun k -> cstring (c2 lib.name stmt k)) in
        let extra = found <> None in
        let p =
          { stmt; ptext = text; extra; inuse = true; reprepared = 0; names = Arrays.list (Array.map (fun s -> Text s) texts);
            texts; bools = decltypes lib stmt n; keys = None }
        in
        if not extra then begin
          (* Past 128 texts, the free ones go first. *)
          if Hashtbl.length c.cache >= 128 then begin
            Hashtbl.filter_map_inplace (fun _ q -> if q.inuse then Some q else (finalize lib q.stmt; None)) c.cache;
            c.last <- None
          end;
          Hashtbl.replace c.cache text p;
          c.last <- Some p
        end;
        Ok p
      | _, more, _ ->
        if more <> 0 then finalize lib more;
        finalize lib stmt;
        Error (failure ctx "statements" (Messages.sql_statements).text)

let bind ctx lib stmt k (v : t) =
  set 0 stmt; set 1 k;
  match v with
  | Missing -> run lib.bind_null 2 ()
  | True | False -> set 2 (if v = True then 1 else 0); run lib.bind_int 3 ()
  | Int i -> set 2 i; run lib.bind_int 3 ()
  | Float x ->
    Bytes.set_int64_ne slots 16 (Int64.bits_of_float x);
    call lib.bind_float 22 slots texts 0;
    Int64.to_int (result ())
  | Text s -> texts.(2) <- s; set 3 (String.length s); set 4 (-1); run lib.bind_text 5 ~text:2 ()
  | _ -> -1

(* Binds each value: an Err for a count that differs, or for a value SQL doesn't take, of Code "convert", which std/sql
   converts and gives again. The statement goes back to the cache on an Err. *)
let bind_all ctx lib c text p params =
  let wanted = c1 lib.count p.stmt in
  if wanted <> Array.length params then begin
    give_back lib c text p;
    Error (failure ctx "07001" (Messages.sql_param_count wanted (Array.length params)).text)
  end
  else begin
    let bad = ref 0 and at = ref 0 in
    Array.iteri (fun k v -> if !bad = 0 then (bad := bind ctx lib p.stmt (k + 1) v; at := k)) params;
    if !bad = 0 then Ok ()
    else begin
      let e =
        if !bad < 0 then failure ctx "convert" (Messages.sql_bad_param (!at + 1) (Value.describe params.(!at))).text
        else last_error ctx lib c
      in
      give_back lib c text p;
      Error e
    end
  end

let list_values ctx name (v : t) =
  match v with
  | Array a -> let a = Value.trim a in Array.init (a.rows * a.cols) (Value.elt a)
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

(* [Run(text, params, conn)]: a cursor on the statement, bound. *)
let run_statement ctx (a : t array) =
  let text = Native.text_arg ctx "sqlite3.Run" a.(0) in
  match conn_arg ctx "sqlite3.Run" a.(2), a.(1) with
  | None, _ -> closed ctx
  | _, v when not (match v with Array _ -> true | _ -> false) ->
    failure ctx "convert" (Messages.need_array "sqlite3.Run" (Value.describe v)).text
  | Some c, _ ->
    let params = list_values ctx "sqlite3.Run" a.(1) in
    with_lib ctx (fun lib ->
        match statement ctx lib c text with
        | Error e -> e
        | Ok p ->
          match bind_all ctx lib c text p params with
          | Error e -> e
          | Ok () ->
            let id = new_id () in
            Hashtbl.replace cursors id { p; text; owner = c; rows = 0 };
            Hashtbl.replace c.live id ();
            Value.ok ctx.w (handle "cursor" id))

let end_cursor lib id cur =
  Hashtbl.remove cursors id;
  Hashtbl.remove cur.owner.live id;
  give_back lib cur.owner cur.text cur.p

let batch_keys = Trie.names [| "Names"; "Cells"; "Done"; "Changed"; "LastId" |]

exception Too_big of int

let cell ctx lib stmt bools k : t =
  match c2 lib.kind stmt k with
  | 1 ->
    ignore (c2 lib.get_int stmt k);
    let r = result () in
    let i = Int64.to_int r in
    if Int64.of_int i <> r then raise (Too_big k);
    if bools.(k) then Value.of_bool (i <> 0) else Int i
  | 2 ->
    set 0 stmt; set 1 k;
    call lib.get_float 7 slots texts 0;
    Float (Int64.float_of_bits (result ()))
  | 3 | 4 as kind ->
    let p = c2 (if kind = 3 then lib.get_text else lib.get_blob) stmt k in
    let n = c2 lib.size stmt k in
    Runtime.reserve ctx ((n / 8) + 2);
    Text (if n = 0 then "" else bytes p n)
  | _ -> Missing

(* A connection and every statement of it. Twice is nothing. *)
let close_conn lib c =
  if not c.closed then begin
    c.closed <- true;
    Hashtbl.iter
      (fun k () ->
         Option.iter (fun cur -> Hashtbl.remove cursors k; if cur.p.extra then finalize lib cur.p.stmt) (Hashtbl.find_opt cursors k))
      c.live;
    Hashtbl.iter (fun _ p -> finalize lib p.stmt) c.cache;
    Hashtbl.reset c.cache;
    c.last <- None;
    ignore (c1 lib.close_v2 c.db);
    Hashtbl.remove conns c.id
  end

(* Parks the fiber for this many seconds: the other fibers run meanwhile. *)
let sleep ctx seconds = Fiber.suspend ctx (fun resume -> let (_ : unit -> unit) = ctx.w.timer seconds resume in ())

(* f () again while SQLite says busy, outside a transaction, at most the wait of the connection: 1 ms, then twice as long,
   up to 50 ms. *)
let retrying ctx c ~give_up f =
  let deadline = Unix.gettimeofday () +. c.wait and pause = ref 0.001 in
  let rec go () =
    match f () with
    | `Busy when Unix.gettimeofday () < deadline ->
      sleep ctx !pause;
      pause := Float.min (!pause *. 2.) 0.05;
      (* Closed while this fiber slept: its statements are finalized. *)
      if c.closed then give_up () else go ()
    | `Busy -> give_up ()
    | `Done r -> r
  in
  go ()

(* SQLite prepares a statement again at its first step when the schema changed: its columns are read again then. *)
let refresh lib p =
  let n = c3 lib.status p.stmt 5 0 in
  if n <> p.reprepared then begin
    p.reprepared <- n;
    let width = c1 lib.columns p.stmt in
    p.texts <- Array.init width (fun k -> cstring (c2 lib.name p.stmt k));
    p.names <- Arrays.list (Array.map (fun s -> Text s) p.texts);
    p.bools <- decltypes lib p.stmt width;
    p.keys <- None
  end

(* [read ctx lib p n cells]: up to n rows into cells, how many, and how it ended: 100 more to come, 101 done, -k-1 the
   integer of column k past 63 bits, else SQLite's code. *)
let read ctx lib p n add =
  let stmt = p.stmt and rows = ref 0 and outcome = ref 100 in
  (try
     while !outcome = 100 && !rows < n do
       outcome := c1 lib.step stmt;
       if !rows = 0 then refresh lib p;
       if !outcome = 100 then begin
         let bools = p.bools in
         let width = Array.length bools in
         (* Memory only: steps are paid after, since paying may let another fiber run, which could close the statement. *)
         Runtime.reserve ctx (width + 1);
         for k = 0 to width - 1 do
           add (cell ctx lib stmt bools k)
         done;
         incr rows
       end
     done
   with Too_big k -> outcome := -k - 1);
  !rows, !outcome

(* Busy, outside a transaction: nothing was written, so the statement can run again. *)
let busy lib c rc = rc land 0xFF = 5 && c1 lib.autocommit c.db <> 0

(* [Next(n, cursor)]: up to n rows, their cells row after row. A busy database before the first row, outside a transaction,
   leaves the cursor as it was, so that its caller can wait and call again. *)
let next ctx (a : t array) =
  let n = match a.(0) with Int n when n > 0 -> n | v -> Runtime.fail ctx Type (Messages.sql_batch (Value.describe v)) in
  let id, cur =
    match a.(1) with
    | Handle { kind = "cursor"; id; _ } -> id, Hashtbl.find_opt cursors id
    | v -> Runtime.fail ctx Type (Messages.sql_need_handle "sqlite3.Next" "cursor" (Value.describe v))
  in
  match cur with
  | None -> closed ctx
  | Some cur ->
    with_lib ctx (fun lib ->
        let c = cur.owner and stmt = cur.p.stmt in
        let cells = ref (Arrays.builder ()) in
        (* A busy database before the first row, outside a transaction, is waited for: nothing was written. *)
        let attempt () =
          cells := Arrays.builder ();
          match read ctx lib cur.p n (Arrays.add ctx ctx.site !cells) with
          | 0, rc when cur.rows = 0 && busy lib c rc -> ignore (c1 lib.reset stmt); `Busy
          | r -> `Done r
        in
        let rows, outcome = retrying ctx c ~give_up:(fun () -> 0, if c.closed then -1000 else 5) attempt in
        let cells = !cells in
        cur.rows <- cur.rows + rows;
        let reply finished =
          Value.ok ctx.w
            (Trie.record batch_keys
               [| cur.p.names; Arrays.built cells; Value.of_bool finished; Int (c1 lib.changes c.db);
                  Int (c1 lib.last_id c.db) |])
        in
        let width = Array.length cur.p.bools in
        let r =
          match outcome with
          | 100 -> reply false
          | 101 -> end_cursor lib id cur; reply true
          | -1000 -> Hashtbl.remove cursors id; closed ctx
          | rc when rc < 0 ->
            let name = cur.p.texts.(-rc - 1) in
            end_cursor lib id cur;
            failure ctx "22003" (Messages.sql_int_past name).text
          | _ ->
            let e = last_error ctx lib c in
            end_cursor lib id cur;
            e
        in
        Runtime.pay ctx (rows * (width + 1));
        r)

(* A connection of the pool: a free one, a new one while fewer than its size are open, else the first to come back,
   waited for until [deadline]. *)
let rec take ctx lib p deadline =
  if p.shut then Error (failure ctx "closed" (Messages.sql_db_closed).text)
  else
    match p.free with
    | c :: rest ->
      p.free <- rest;
      if c.broken || c.closed then begin
        close_conn lib c;
        p.opened <- p.opened - 1;
        take ctx lib p deadline
      end
      else Ok c
    | [] when p.opened < p.size ->
      p.opened <- p.opened + 1;
      (match open_conn ctx lib p.path with
       | Error e -> p.opened <- p.opened - 1; Error e
       | Ok c ->
         c.wait <- p.pool_wait;
         let pragmas = (if p.path = ":memory:" then "" else "pragma journal_mode = wal; ") ^ "pragma foreign_keys = on" in
         let set_up () =
           set 0 c.db; texts.(1) <- pragmas; set 2 0; set 3 0; set 4 0;
           match run lib.exec 5 ~text:1 () with
           | 0 -> `Done (Ok c)
           | rc when rc land 0xFF = 5 -> `Busy
           | _ -> `Done (Error (last_error ctx lib c))
         in
         match retrying ctx c ~give_up:(fun () -> Error (if c.closed then closed ctx else last_error ctx lib c)) set_up with
         | Ok c -> Ok c
         | Error e -> close_conn lib c; p.opened <- p.opened - 1; Error e)
    | [] ->
      let left = deadline -. Unix.gettimeofday () in
      if left <= 0. then Error (failure ctx "pool" (Messages.sql_pool p.pool_wait).text)
      else begin
        let mine = ref ignore in
        (match
           Fiber.suspend ctx (fun resume ->
               let parked = ref true in
               let wake () = if !parked then (parked := false; resume ()) in
               mine := wake;
               p.waiters <- p.waiters @ [ wake ];
               let (_ : unit -> unit) =
                 ctx.w.timer left (fun () ->
                     if !parked then begin
                       p.waiters <- List.filter (fun w -> w != wake) p.waiters;
                       wake ()
                     end)
               in
               ())
         with
         | () -> ()
         | exception e ->
           (* Stopped by fiber.Cancel, perhaps woken for a connection it will never take: the next one takes it. *)
           p.waiters <- List.filter (fun w -> w != !mine) p.waiters;
           (match p.free, p.waiters with
            | _ :: _, wake :: rest -> p.waiters <- rest; wake ()
            | _ -> ());
           raise e);
        take ctx lib p deadline
      end

(* A connection back in its pool, or closed if the pool is, or if it is broken; the first fiber waiting is woken. *)
let give lib p c =
  if not (p.shut || c.broken || c.closed) && c1 lib.autocommit c.db = 0 then begin
    (* A transaction left open, as by a script stopped halfway, is rolled back: nothing written next is lost with it. *)
    set 0 c.db; texts.(1) <- "rollback"; set 2 0; set 3 0; set 4 0;
    ignore (run lib.exec 5 ~text:1 ())
  end;
  if p.shut || c.broken || c.closed then begin
    close_conn lib c;
    p.opened <- p.opened - 1
  end
  else p.free <- c :: p.free;
  match p.waiters with
  | wake :: rest -> p.waiters <- rest; wake ()
  | [] -> ()

let seconds_arg ctx (v : t) =
  match v with
  | Int i when i >= 0 -> float_of_int i
  | Float x when x >= 0. -> x
  | v -> Runtime.fail ctx Type (Messages.bad_timeout (Value.describe v))

(* [Pool(path, size, wait)]: connections opened when needed, with WAL for a file and foreign keys. *)
let new_pool ctx (a : t array) =
  let path = path_arg ctx "sqlite3.Pool" a.(0) in
  let size = match a.(1) with Int n when n >= 1 -> n | v -> Runtime.fail ctx Type (Messages.sql_pool_size (Value.describe v)) in
  let wait = seconds_arg ctx a.(2) in
  with_lib ctx (fun _ ->
      let id = new_id () in
      Hashtbl.replace pools id { path; size; pool_wait = wait; free = []; opened = 0; shut = false; waiters = [] };
      Value.ok ctx.w (handle "pool" id))

let pool_arg ctx name (v : t) =
  match v with
  | Handle { kind = "pool"; id; _ } -> Hashtbl.find_opt pools id
  | v -> Runtime.fail ctx Type (Messages.sql_need_handle name "pool" (Value.describe v))

(* f on a connection: the one given, or one of the pool given, which goes back after f, a panic too. *)
let using ctx lib name (v : t) f =
  match v with
  | Handle { kind = "connection"; _ } -> (match conn_arg ctx name v with Some c -> f c | None -> closed ctx)
  | Handle { kind = "pool"; id; _ } ->
    (match Hashtbl.find_opt pools id with
     | None -> closed ctx
     | Some p ->
       match take ctx lib p (Unix.gettimeofday () +. p.pool_wait) with
       | Error e -> e
       | Ok c ->
         match f c with
         | r -> give lib p c; r
         | exception e -> give lib p c; raise e)
  | v -> Runtime.fail ctx Type (Messages.sql_need_handle name "pool or connection" (Value.describe v))

(* Runs one statement to its end, or to [limit] rows, each cell given to [add]: its prepared statement, or an Err. *)
let whole ctx lib c text (params : t) limit add =
  match params with
  | Array a ->
    let a = Value.trim a in
    let params = Array.init (a.rows * a.cols) (Value.elt a) in
    (match statement ctx lib c text with
     | Error e -> Error e
     | Ok p ->
       match bind_all ctx lib c text p params with
       | Error e -> Error e
       | Ok () ->
         let read_rows = ref 0 in
         let attempt () =
           match (let (n, _) as r = read ctx lib p limit add in read_rows := !read_rows + n; r) with
           | 0, rc when busy lib c rc -> ignore (c1 lib.reset p.stmt); `Busy
           | _, (100 | 101) -> give_back lib c text p; `Done (Ok p)
           | _, rc when rc < 0 ->
             give_back lib c text p;
             `Done (Error (failure ctx "22003" (Messages.sql_int_past p.texts.(-rc - 1)).text))
           | _ ->
             let e = last_error ctx lib c in
             give_back lib c text p;
             `Done (Error e)
         in
         let give_up () =
           let e = if c.closed then closed ctx else last_error ctx lib c in
           give_back lib c text p;
           Error e
         in
         let r = retrying ctx c ~give_up attempt in
         Runtime.pay ctx (!read_rows * (Array.length p.bools + 1));
         r)
  | v -> Error (failure ctx "convert" (Messages.need_array "sqlite3.Query" (Value.describe v)).text)

(* [Query(text, params, db, limit)]: every row, or the first limit, as maps whose keys are the names made public names;
   with [one], the first row or missing. *)
let query ~one ctx (a : t array) =
  let text = Native.text_arg ctx "sqlite3.Query" a.(0) in
  let limit =
    match if one then Int 1 else if Array.length a > 3 then a.(3) else Undef with
    | Undef | Missing -> max_int
    | Int n when n > 0 -> n
    | v -> Runtime.fail ctx Type (Messages.sql_batch (Value.describe v))
  in
  with_lib ctx (fun lib ->
      using ctx lib "sqlite3.Query" a.(2) (fun c ->
          let cells = Vec.create () in
          match whole ctx lib c text a.(1) limit (Vec.add_last cells) with
          | Error e -> e
          | Ok p ->
            if Array.length p.texts = 0 || (one && Vec.length cells = 0) then
              Value.ok ctx.w (if one then Missing else Arrays.list [||])
            else begin
              let keys = match p.keys with Some k -> k | None -> let k = Columns.row_keys true p.texts in p.keys <- Some k; k in
              match keys with
              | Error m -> failure ctx "names" m
              | Ok keys when one -> Value.ok ctx.w (Trie.record keys (Array.map Value.share (Vec.to_array cells)))
              | Ok keys -> Value.ok ctx.w (Columns.make_rows ctx keys (Vec.to_array cells))
            end))

let changed_keys = Trie.names [| "Changed"; "LastId" |]

(* [Exec(text, params, db)]: runs a statement to its end: an Ok of {Changed, LastId}. *)
let exec ctx (a : t array) =
  let text = Native.text_arg ctx "sqlite3.Exec" a.(0) in
  with_lib ctx (fun lib ->
      using ctx lib "sqlite3.Exec" a.(2) (fun c ->
          match whole ctx lib c text a.(1) max_int ignore with
          | Error e -> e
          | Ok _ -> Value.ok ctx.w (Trie.record changed_keys [| Int (c1 lib.changes c.db); Int (c1 lib.last_id c.db) |])))

(* [Script(text, db)]: several statements, no parameters, one after the other. Each waits for a busy database as one
   statement does, before its first step, so that none runs twice. *)
let script ctx (a : t array) =
  let text = Native.text_arg ctx "sqlite3.Script" a.(0) in
  with_lib ctx (fun lib ->
      using ctx lib "sqlite3.Script" a.(1) (fun c ->
          if String.contains text '\000' then failure ctx "statements" (Messages.sql_zero_byte "a script").text
          else
            let () = no_directory ctx text in
            let rec go text =
              match prepare lib c text with
              | rc, _, _ when rc <> 0 -> last_error ctx lib c
              | _, 0, _ -> Value.ok ctx.w Missing
              | _, stmt, rest ->
                let rec drain first =
                  match c1 lib.step stmt with
                  | 100 -> drain false
                  | 101 -> `Done (Ok ())
                  | rc when first && busy lib c rc -> ignore (c1 lib.reset stmt); `Busy
                  | _ -> `Done (Error (last_error ctx lib c))
                in
                let give_up () = Error (if c.closed then closed ctx else last_error ctx lib c) in
                let r = retrying ctx c ~give_up (fun () -> drain true) in
                finalize lib stmt;
                match r with
                | Ok () -> go rest
                | Error e -> e
            in
            go text))

(* [Close(x)]: a cursor before its end, or a connection and every statement of it. Twice is nothing. *)
let close ctx (a : t array) =
  (match !library, a.(0) with
   | Some lib, Handle { kind = "cursor"; id; _ } -> Option.iter (end_cursor lib id) (Hashtbl.find_opt cursors id)
   | Some lib, Handle { kind = "connection"; id; _ } -> Option.iter (close_conn lib) (Hashtbl.find_opt conns id)
   | Some lib, Handle { kind = "pool"; id; _ } ->
     Option.iter
       (fun p ->
          p.shut <- true;
          List.iter (close_conn lib) p.free;
          p.opened <- p.opened - List.length p.free;
          p.free <- [];
          let waiting = p.waiters in
          p.waiters <- [];
          List.iter (fun wake -> wake ()) waiting)
       (Hashtbl.find_opt pools id)
   | _, (Handle { kind = "cursor" | "connection" | "pool"; _ }) -> ()
   | _, v -> Runtime.fail ctx Type (Messages.sql_need_handle "sqlite3.Close" "pool, connection or cursor" (Value.describe v)));
  Missing

(* The code of each native, by name: the binary holds their names and arities (src/sys/sys_modules.ml). *)
let natives =
  [ "Pool", new_pool;
    "Take",
    (fun ctx a ->
       match pool_arg ctx "sqlite3.Take" a.(0) with
       | None -> closed ctx
       | Some p ->
         with_lib ctx (fun lib ->
             match take ctx lib p (Unix.gettimeofday () +. p.pool_wait) with
             | Ok c ->
               (* A handle of its own, which Give forgets: kept past its end, it finds nothing. *)
               let lease = new_id () in
               Hashtbl.replace conns lease c;
               Value.ok ctx.w (handle "connection" lease)
             | Error e -> e));
    "Give",
    (fun ctx a ->
       (match a.(0), pool_arg ctx "sqlite3.Give" a.(1), !library with
        | Handle { kind = "connection"; id; _ }, Some p, Some lib when id <> 0 ->
          Option.iter
            (fun c -> if c.id <> id then begin Hashtbl.remove conns id; give lib p c end)
            (Hashtbl.find_opt conns id)
        | _ -> ());
       Missing);
    "Query", query ~one:false;
    "One", query ~one:true;
    "Exec", exec;
    "Run", run_statement;
    "Next", next;
    "Script", script;
    "Close", close;
    "Version", (fun ctx _ -> with_lib ctx (fun lib -> Value.ok ctx.w (Text (cstring (run lib.version 0 ()))))) ]
