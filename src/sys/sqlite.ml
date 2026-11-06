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
  autocommit : int; exec : int;
}

(* A statement and what it says of its columns, read once. *)
type prepared = { stmt : int; names : t; bools : bool array  (** the columns declared BOOLEAN *) }

type conn = {
  db : int;
  cache : (string, prepared list) Hashtbl.t;  (** free statements by text: one in use is never handed out twice *)
  mutable cached : int;
  mutable broken : bool;
  mutable closed : bool;
  live : (int, unit) Hashtbl.t;  (** its cursors *)
}

type cursor = { p : prepared; text : string; owner : conn; mutable rows : int }

let library = ref None
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
let busy_keys = Trie.names [| "Kind"; "Code"; "Message"; "Retry" |]

let failure ctx ?(retry = false) code message =
  let code = Text code and message = Text message and kind = Text "sql" in
  Value.err ctx.w
    (if retry then Trie.record busy_keys [| kind; code; message; True |] else Trie.record error_keys [| kind; code; message |])

let sqlite_code rc = match List.assoc_opt rc codes with Some c -> c | None -> Printf.sprintf "sqlite-%d" rc

(* The error of the last call on [c]: an I/O error or a damaged file leave the connection broken. *)
let last_error ctx lib ?retry c =
  let rc = c1 lib.errcode c.db in
  if List.mem (rc land 0xFF) [ 10; 11; 14; 21; 26 ] then c.broken <- true;
  failure ctx ?retry (sqlite_code rc) (cstring (c1 lib.errmsg c.db))

let load ctx =
  Runtime.check_perm ctx Ffi (Some "sqlite3");
  match !library with
  | Some lib -> Ok lib
  | None ->
    let try_file (found, reason) path =
      if found <> 0 then found, reason
      else
        let h = dlopen path in
        h, if h = 0 && reason = "" then dlerror () else reason
    in
    (match List.fold_left try_file (0, "") (C.candidates "sqlite3" (Some "0")) with
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
           version = f "libversion"; autocommit = f "get_autocommit"; exec = f "exec" }
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
   double-quoted texts, texts and BLOBs of 100 MB at most, nothing attached, and no busy wait: pkg/sqlite retries, so the
   other fibers run meanwhile. *)
let open_db ctx (a : t array) =
  let path = Native.text_arg ctx "sqlite3.Open" a.(0) in
  zero_free ctx "a path" path;
  if path <> ":memory:" then begin
    Runtime.check_perm ctx Read (Some path);
    Runtime.check_perm ctx Write (Some path)
  end;
  with_lib ctx (fun lib ->
      let out = Lazy.force scratch in
      texts.(0) <- path;
      set 1 out; set 2 (0x2 lor 0x4 lor 0x8000 lor 0x02000000); set 3 0;
      let rc = run lib.open_v2 4 ~text:0 () and db = Int64.to_int (peek out 8) in
      let c = { db; cache = Hashtbl.create 16; cached = 0; broken = false; closed = false; live = Hashtbl.create 4 } in
      if rc <> 0 then begin
        let e = if db = 0 then failure ctx (sqlite_code rc) "out of memory" else last_error ctx lib c in
        if db <> 0 then ignore (c1 lib.close_v2 db);
        e
      end
      else begin
        List.iter (fun (op, on) -> ignore (db_config lib.config db op on)) [ 1010, 1; 1017, 0; 1005, 0; 1013, 0; 1014, 0 ];
        ignore (c3 lib.limit db 0 100_000_000);
        ignore (c3 lib.limit db 7 0);
        let id = new_id () in
        Hashtbl.replace conns id c;
        Value.ok ctx.w (handle "connection" id)
      end)

let conn_arg ctx name (v : t) =
  match v with
  | Handle { kind = "connection"; id; _ } -> Hashtbl.find_opt conns id
  | _ -> Runtime.fail ctx Type (Messages.sql_need_handle name "connection" (Value.describe v))

let closed ctx = failure ctx "closed" (Messages.sql_closed).text
let finalize lib stmt = ignore (c1 lib.finalize stmt)

(* A statement back in the cache, reset; past 128, the cache is emptied first. *)
let give_back lib c text p =
  ignore (c1 lib.reset p.stmt);
  ignore (c1 lib.clear p.stmt);
  if c.closed || c.broken then finalize lib p.stmt
  else begin
    if c.cached >= 128 then begin
      Hashtbl.iter (fun _ l -> List.iter (fun p -> finalize lib p.stmt) l) c.cache;
      Hashtbl.reset c.cache;
      c.cached <- 0
    end;
    Hashtbl.replace c.cache text (p :: Option.value ~default:[] (Hashtbl.find_opt c.cache text));
    c.cached <- c.cached + 1
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

(* One statement: text after it that holds another is an error, so none rides in on a value glued by hand. *)
let statement ctx lib c text =
  match Hashtbl.find_opt c.cache text with
  | Some (p :: rest) ->
    Hashtbl.replace c.cache text rest;
    c.cached <- c.cached - 1;
    Ok p
  | _ ->
    zero_free ctx "a statement" text;
    let rc, stmt, rest = prepare lib c text in
    if rc <> 0 then Error (last_error ctx lib c)
    else if stmt = 0 then Error (failure ctx "statements" (Messages.sql_no_statement).text)
    else
      match prepare lib c rest with
      | 0, 0, _ ->
        let n = c1 lib.columns stmt in
        let names = Arrays.list (Array.init n (fun k -> Text (cstring (c2 lib.name stmt k)))) in
        Ok { stmt; names; bools = decltypes lib stmt n }
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
  | v -> Runtime.fail ctx Type (Messages.sql_bad_param k (Value.describe v))

let list_values ctx name (v : t) =
  match v with
  | Array a -> let a = Value.trim a in Array.init (a.rows * a.cols) (Value.elt a)
  | _ -> Runtime.fail ctx Type (Messages.need_array name (Value.describe v))

(* [Run(text, params, conn)]: a cursor on the statement, bound. *)
let run_statement ctx (a : t array) =
  let text = Native.text_arg ctx "sqlite3.Run" a.(0) and params = list_values ctx "sqlite3.Run" a.(1) in
  match conn_arg ctx "sqlite3.Run" a.(2) with
  | None -> closed ctx
  | Some c ->
    with_lib ctx (fun lib ->
        match statement ctx lib c text with
        | Error e -> e
        | Ok p ->
          let stmt = p.stmt in
          let wanted = c1 lib.count stmt in
          if wanted <> Array.length params then begin
            give_back lib c text p;
            failure ctx "07001" (Messages.sql_param_count wanted (Array.length params)).text
          end
          else
            let bad = ref 0 in
            Array.iteri (fun k v -> if !bad = 0 then bad := bind ctx lib stmt (k + 1) v) params;
            if !bad <> 0 then begin
              let e = last_error ctx lib c in
              give_back lib c text p;
              e
            end
            else begin
              let id = new_id () in
              Hashtbl.replace cursors id { p; text; owner = c; rows = 0 };
              Hashtbl.replace c.live id ();
              Value.ok ctx.w (handle "cursor" id)
            end)

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
        let c = cur.owner and stmt = cur.p.stmt and bools = cur.p.bools in
        let width = Array.length bools in
        let cells = Arrays.builder () and rows = ref 0 and outcome = ref 100 in
        (try
           while !outcome = 100 && !rows < n do
             outcome := c1 lib.step stmt;
             if !outcome = 100 then begin
               Runtime.build ctx (width + 1);
               for k = 0 to width - 1 do
                 Arrays.add ctx ctx.site cells (cell ctx lib stmt bools k)
               done;
               incr rows
             end
           done
         with Too_big k -> outcome := -k - 1);
        cur.rows <- cur.rows + !rows;
        let reply finished =
          Value.ok ctx.w
            (Trie.record batch_keys
               [| cur.p.names; Arrays.built cells; Value.of_bool finished; Int (c1 lib.changes c.db);
                  Int (c1 lib.last_id c.db) |])
        in
        match !outcome with
        | 100 -> reply false
        | 101 -> end_cursor lib id cur; reply true
        | rc when rc < 0 ->
          end_cursor lib id cur;
          let name = cstring (c2 lib.name stmt (-rc - 1)) in
          failure ctx "22003" (Messages.sql_int_past name).text
        | rc when rc land 0xFF = 5 && cur.rows = 0 && c1 lib.autocommit c.db <> 0 ->
          ignore (c1 lib.reset stmt);
          last_error ctx lib ~retry:true c
        | _ ->
          let e = last_error ctx lib c in
          end_cursor lib id cur;
          e)

(* [Script(text, conn)]: several statements, no parameters. *)
let script ctx (a : t array) =
  let text = Native.text_arg ctx "sqlite3.Script" a.(0) in
  zero_free ctx "a script" text;
  match conn_arg ctx "sqlite3.Script" a.(1) with
  | None -> closed ctx
  | Some c ->
    with_lib ctx (fun lib ->
        set 0 c.db; texts.(1) <- text; set 2 0; set 3 0; set 4 0;
        if run lib.exec 5 ~text:1 () = 0 then Value.ok ctx.w Missing else last_error ctx lib c)

(* [Close(x)]: a cursor before its end, or a connection and every statement of it. Twice is nothing. *)
let close ctx (a : t array) =
  (match !library, a.(0) with
   | Some lib, Handle { kind = "cursor"; id; _ } -> Option.iter (end_cursor lib id) (Hashtbl.find_opt cursors id)
   | Some lib, Handle { kind = "connection"; id; _ } ->
     Option.iter
       (fun c ->
          c.closed <- true;
          Hashtbl.iter (fun k () -> Option.iter (fun cur -> Hashtbl.remove cursors k; finalize lib cur.p.stmt) (Hashtbl.find_opt cursors k)) c.live;
          Hashtbl.iter (fun _ l -> List.iter (fun p -> finalize lib p.stmt) l) c.cache;
          ignore (c1 lib.close_v2 c.db);
          Hashtbl.remove conns id)
       (Hashtbl.find_opt conns id)
   | _, (Handle { kind = "cursor" | "connection"; _ }) -> ()
   | _, v -> Runtime.fail ctx Type (Messages.sql_need_handle "sqlite3.Close" "connection or cursor" (Value.describe v)));
  Missing

let natives =
  [ "Open", Native.nat ~params:[| "path" |] "Open" 1 1 open_db;
    "Run", Native.nat ~params:[| "text"; "params"; "conn" |] "Run" 3 3 run_statement;
    "Next", Native.nat ~params:[| "n"; "cursor" |] "Next" 2 2 next;
    "Script", Native.nat ~params:[| "text"; "conn" |] "Script" 2 2 script;
    "Close", Native.nat ~params:[| "x" |] "Close" 1 1 close;
    "Broken",
    Native.nat ~params:[| "conn" |] "Broken" 1 1 (fun ctx a ->
        Value.of_bool (match conn_arg ctx "sqlite3.Broken" a.(0) with Some c -> c.broken | None -> true));
    "Version",
    Native.nat "Version" 0 0 (fun ctx _ -> with_lib ctx (fun lib -> Value.ok ctx.w (Text (cstring (run lib.version 0 ()))))) ]
