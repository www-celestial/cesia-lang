(* What a running server tells of itself: std/log, a JSON object per line, and std/metrics, counters and histograms that
   a scrape reads in the text format of Prometheus. Both in OCaml: a line or a count costs a microsecond, not a call
   through Cesia for each part. *)
open Cesia
open Types

(* The time in UTC, to the millisecond, as ISO 8601 writes it. The part up to the second is written once a second: a
   server writes many lines in each. *)
let second = ref (-1) and upto = ref ""

let stamp now =
  let whole = int_of_float now in
  if whole <> !second then begin
    let t = Unix.gmtime (Float.of_int whole) in
    second := whole;
    upto := Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d." (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec
  end;
  let ms = int_of_float ((now -. Float.of_int whole) *. 1000.) in
  Printf.sprintf "%s%03dZ" !upto (min ms 999)

(* One line on the standard output, which keeps its order with io.Print: {"time", "level", "message"}, then the fields of
   a struct or a dictionary. *)
let line level ctx (a : t array) =
  let w = ctx.w in
  let message = Native.text_arg ctx level a.(0) in
  let fields = match if Array.length a > 1 then a.(1) else Undef with
    | Undef | Missing -> ""
    | (Dict _ | Struct _) as v ->
      let s = Json.text ctx v in
      if String.length s <= 2 then "" else "," ^ String.sub s 1 (String.length s - 2)
    | v -> Runtime.fail ctx Type (Messages.log_fields (Value.describe v))
  in
  Printf.bprintf w.out "{\"time\":\"%s\",\"level\":\"%s\",\"message\":%s%s}\n" (stamp (Unix.gettimeofday ())) level
    (Json.text ctx (Text message)) fields;
  if Buffer.length w.out > 65536 then Runtime.flush_out w;
  Missing

let log_natives =
  List.map
    (fun (name, level) -> name, Native.nat ~params:[| "message"; "fields" |] name 1 2 (line level))
    [ "Info", "info"; "Warn", "warn"; "Error", "error" ]

(* The buckets of a histogram, in seconds: those of Prometheus's own clients, from 5 ms to 10 s. *)
let buckets = [| 0.005; 0.01; 0.025; 0.05; 0.1; 0.25; 0.5; 1.; 2.5; 5.; 10. |]

type series =
  | Count of float ref
  | Spread of { counts : int array; mutable sum : float; mutable n : int }

type family = { kind : string; series : (string, series) Hashtbl.t; mutable order : string list }

let valid first rest s =
  s <> "" && first s.[0] && String.for_all rest s

let letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'
let digit c = c >= '0' && c <= '9'

(* The labels of a series as Prometheus writes them, {method="GET",status="200"}, from a struct or a dictionary. *)
let labels ctx (v : t) =
  let pairs = match v with
    | Undef | Missing -> []
    | Dict _ ->
      let o = Value.items v in
      List.init (Array.length o / 2) (fun k -> Value.text_of ctx o.(2 * k), o.((2 * k) + 1))
    | Struct { shape; fields; _ } -> List.init (Trie.nvals fields) (fun k -> shape.names.(k), Trie.vget fields k)
    | v -> Runtime.fail ctx Type (Messages.metric_labels (Value.describe v))
  in
  let escape s =
    if not (String.exists (fun c -> c = '\\' || c = '"' || c = '\n') s) then s
    else String.concat "" (List.map (function '\\' -> "\\\\" | '"' -> "\\\"" | '\n' -> "\\n" | c -> String.make 1 c) (List.of_seq (String.to_seq s)))
  in
  let one (k, x) =
    if not (valid letter (fun c -> letter c || digit c) k) then Runtime.fail ctx Type (Messages.metric_name k);
    String.concat "" [ k; "=\""; escape (Value.text_of ctx x); "\"" ]
  in
  String.concat "," (List.map one pairs)

let natives () =
  let families : (string, family) Hashtbl.t = Hashtbl.create 16 and order = ref [] in
  let series ctx kind (a : t array) make =
    let name = Native.text_arg ctx "metrics" a.(0) in
    if not (valid (fun c -> letter c || c = ':') (fun c -> letter c || digit c || c = ':') name) then
      Runtime.fail ctx Type (Messages.metric_name name);
    let f =
      match Hashtbl.find_opt families name with
      | Some f when f.kind = kind -> f
      | Some f -> Runtime.fail ctx Type (Messages.metric_kind name f.kind)
      | None ->
        let f = { kind; series = Hashtbl.create 4; order = [] } in
        Hashtbl.replace families name f;
        order := name :: !order;
        f
    in
    let key = labels ctx (if Array.length a > 2 then a.(2) else Undef) in
    match Hashtbl.find_opt f.series key with
    | Some s -> s
    | None ->
      let s = make () in
      Hashtbl.replace f.series key s;
      f.order <- key :: f.order;
      s
  in
  let amount ctx name (v : t) =
    match v with
    | Int i -> Float.of_int i
    | Float x when Float.is_finite x -> x
    | v -> Runtime.fail ctx Type (Messages.need_number name (Value.describe v))
  in
  let add ctx (a : t array) =
    let n = if Array.length a > 1 && a.(1) <> Undef then amount ctx "metrics.Add" a.(1) else 1. in
    if n < 0. then Runtime.fail ctx Type (Messages.metric_negative n);
    (match series ctx "counter" a (fun () -> Count (ref 0.)) with Count c -> c := !c +. n | Spread _ -> ());
    Missing
  in
  let observe ctx (a : t array) =
    let x = amount ctx "metrics.Observe" a.(1) in
    (match series ctx "histogram" a (fun () -> Spread { counts = Array.make (Array.length buckets) 0; sum = 0.; n = 0 }) with
     | Spread s ->
       Array.iteri (fun k bound -> if x <= bound then s.counts.(k) <- s.counts.(k) + 1) buckets;
       s.sum <- s.sum +. x;
       s.n <- s.n + 1
     | Count _ -> ());
    Missing
  in
  let text _ _ =
    let b = Buffer.create 1024 in
    let number x = if Float.is_integer x && Float.abs x < 1e15 then Printf.sprintf "%.0f" x else Value.float_text x in
    let braces key extra = match key, extra with "", "" -> "" | k, "" | "", k -> "{" ^ k ^ "}" | k, e -> "{" ^ k ^ "," ^ e ^ "}" in
    List.iter
      (fun name ->
         let f = Hashtbl.find families name in
         Printf.bprintf b "# TYPE %s %s\n" name f.kind;
         List.iter
           (fun key ->
              match Hashtbl.find f.series key with
              | Count c -> Printf.bprintf b "%s%s %s\n" name (braces key "") (number !c)
              | Spread s ->
                Array.iteri
                  (fun k bound -> Printf.bprintf b "%s_bucket%s %d\n" name (braces key (Printf.sprintf "le=\"%s\"" (number bound))) s.counts.(k))
                  buckets;
                Printf.bprintf b "%s_bucket%s %d\n" name (braces key "le=\"+Inf\"") s.n;
                Printf.bprintf b "%s_sum%s %s\n%s_count%s %d\n" name (braces key "") (number s.sum) name (braces key "") s.n)
           (List.rev f.order))
      (List.rev !order);
    Text (Buffer.contents b)
  in
  [ "Add", Native.nat ~params:[| "name"; "n"; "labels" |] "Add" 1 3 add;
    "Observe", Native.nat ~params:[| "name"; "value"; "labels" |] "Observe" 2 3 observe;
    "Text", Native.nat "Text" 0 0 text ]
