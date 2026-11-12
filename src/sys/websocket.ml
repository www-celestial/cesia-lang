open Cesia
open Types

(* RFC 6455 §1.3: the key of a handshake and this GUID give the answer of the server. *)
let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
let max_frame = 1048576
let default_idle = 300

(* SHA-1, FIPS 180-4 §6.1, which the handshake asks for (RFC 6455 §4.2.2): a check of the key, no signature. *)
let sha1 s =
  let n = String.length s in
  let b = Bytes.make ((((n + 8) / 64) + 1) * 64) '\000' in
  Bytes.blit_string s 0 b 0 n;
  Bytes.set b n '\x80';
  Bytes.set_int64_be b (Bytes.length b - 8) (Int64.of_int (8 * n));
  let m = 0xFFFFFFFF and h = [| 0x67452301; 0xEFCDAB89; 0x98BADCFE; 0x10325476; 0xC3D2E1F0 |] and w = Array.make 80 0 in
  let rol x k = ((x lsl k) lor (x lsr (32 - k))) land m in
  for block = 0 to (Bytes.length b / 64) - 1 do
    for t = 0 to 15 do w.(t) <- Int32.to_int (Bytes.get_int32_be b ((64 * block) + (4 * t))) land m done;
    for t = 16 to 79 do w.(t) <- rol (w.(t - 3) lxor w.(t - 8) lxor w.(t - 14) lxor w.(t - 16)) 1 done;
    let v = Array.copy h in
    for t = 0 to 79 do
      let x = v.(1) and y = v.(2) and z = v.(3) in
      let f, k =
        if t < 20 then (x land y) lor (lnot x land z), 0x5A827999
        else if t < 40 then x lxor y lxor z, 0x6ED9EBA1
        else if t < 60 then (x land y) lor (x land z) lor (y land z), 0x8F1BBCDC
        else x lxor y lxor z, 0xCA62C1D6
      in
      let next = (rol v.(0) 5 + f + v.(4) + k + w.(t)) land m in
      v.(4) <- z; v.(3) <- y; v.(2) <- rol x 30; v.(1) <- v.(0); v.(0) <- next
    done;
    Array.iteri (fun i x -> h.(i) <- (h.(i) + x) land m) v
  done;
  String.init 20 (fun i -> Char.chr ((h.(i / 4) lsr (24 - (8 * (i mod 4)))) land 255))

(* Base64 with padding, RFC 4648 §4. *)
let base64 s =
  let digits = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" and n = String.length s in
  String.init ((n + 2) / 3 * 4) (fun i ->
      let g = i / 4 * 3 in
      let byte k = if g + k < n then Char.code s.[g + k] else 0 in
      if i mod 4 > n - g then '='
      else digits.[(((byte 0 lsl 16) lor (byte 1 lsl 8) lor byte 2) lsr (18 - (6 * (i mod 4)))) land 63])

let answer key = base64 (sha1 (key ^ guid))

(* The seed that OCaml's runtime takes from the system for Random.self_init (runtime/sys.c and runtime/win32.c of OCaml
   5.5): 12 bytes from getentropy, else /dev/urandom, on Linux and macOS, one per number; three numbers of 32 bits from
   rand_s on Windows. Without them, it gives the time and the process ids instead, in another count of numbers: refused. *)
external random_seed : unit -> int array = "caml_sys_random_seed"

let random_bytes ctx n =
  let b = Buffer.create (n + 12) in
  while Buffer.length b < n do
    match random_seed () with
    | [| _; _; _ |] as s when Sys.win32 ->
      Array.iter (fun x -> for k = 0 to 3 do Buffer.add_char b (Char.chr ((x lsr (8 * k)) land 255)) done) s
    | s when (not Sys.win32) && Array.length s = 12 && Array.for_all (fun x -> x >= 0 && x < 256) s ->
      Array.iter (fun x -> Buffer.add_char b (Char.chr x)) s
    | _ -> Runtime.fail ctx User Messages.no_random
  done;
  Buffer.sub b 0 n

(* [n] bytes of [s] from [from] into [out] at [at], each one xor the byte of [key] at its place, the key of 4 bytes
   repeated (RFC 6455 §5.3), eight at a time; a copy when [key] is empty. *)
let mask s from n key out at =
  if key = "" then Bytes.blit_string s from out at n
  else begin
    let k = Int64.of_int32 (String.get_int32_le key 0) in
    let k8 = Int64.logor (Int64.logand k 0xFFFFFFFFL) (Int64.shift_left k 32) and whole = n / 8 * 8 in
    let i = ref 0 in
    while !i < whole do
      Bytes.set_int64_le out (at + !i) (Int64.logxor (String.get_int64_le s (from + !i)) k8);
      i := !i + 8
    done;
    for j = whole to n - 1 do Bytes.set out (at + j) (Char.chr (Char.code s.[from + j] lxor Char.code key.[j land 3])) done
  end

(* A whole frame, RFC 6455 §5.2: masked by [key] as a client's, or not, as a server's, when [key] is empty. *)
let frame opcode payload key =
  let n = String.length payload and m = String.length key in
  let ext = if n < 126 then 0 else if n < 65536 then 2 else 8 in
  let b = Bytes.create (2 + ext + m + n) in
  Bytes.set_uint8 b 0 (128 + opcode);
  Bytes.set_uint8 b 1 ((if m > 0 then 128 else 0) + match ext with 0 -> n | 2 -> 126 | _ -> 127);
  if ext = 2 then Bytes.set_uint16_be b 2 n else if ext = 8 then Bytes.set_int64_be b 2 (Int64.of_int n);
  Bytes.blit_string key 0 b (2 + ext) m;
  mask payload 0 n key b (2 + ext + m);
  Bytes.unsafe_to_string b

(* The length of the payload of the frame at [at] and where its mask or its payload starts, once the bytes that tell
   are there. A length of 64 bits with its first bit set gives -1, and one past 2^56 max_int. *)
let length s at =
  let left = String.length s - at in
  if left < 2 then None
  else
    match Char.code s.[at + 1] land 127 with
    | 126 when left >= 4 -> Some (String.get_uint16_be s (at + 2), at + 4)
    | 127 when left >= 10 ->
      let first = Char.code s.[at + 2] in
      Some ((if first >= 128 then -1 else if first > 0 then max_int else Int64.to_int (String.get_int64_be s (at + 2))), at + 10)
    | 126 | 127 -> None
    | n -> Some (n, at + 2)

(* The frame of a client at [at] of a buffer, as the server reads it: [`More] while it isn't all there, [`Bad] for one it
   refuses (not masked, a fragment, a reserved bit, past MaxFrame), else its opcode, its payload and where the next starts. *)
let server_frame s at =
  match length s at with
  | None -> `More
  | Some (n, p) ->
    let b0 = Char.code s.[at] in
    if Char.code s.[at + 1] < 128 || n < 0 || n > max_frame || b0 land 0x70 <> 0 || b0 < 128 then `Bad
    else if String.length s < p + 4 + n then `More
    else begin
      let out = Bytes.create n in
      mask s (p + 4) n (String.sub s p 4) out 0;
      `Frame (b0 land 15, Bytes.unsafe_to_string out, p + 4 + n)
    end

let needs_keys = Trie.names [| "Needs" |]
let code_keys = Trie.names [| "Code" |]
let frame_keys = Trie.names [| "Fin"; "Opcode"; "Payload"; "Next" |]

(* The close codes an endpoint may send, RFC 6455 §7.4.1 and §7.4.2, with 1012 to 1014 of IANA's registry. *)
let sendable c = (c >= 1000 && c <= 1003) || (c >= 1007 && c <= 1014) || (c >= 3000 && c <= 4999)

(* The frame of a server at [at], from 1, for a client: {Needs} the bytes it takes from [at] while they aren't all there;
   {Code} the code to close with when RFC 6455 refuses it: 1002 for a reserved bit or opcode (§5.2), a mask (§5.1), a
   control frame fragmented or past 125 bytes (§5.5), a continuation with no message begun or a message begun inside
   another ([kind], the opcode of the message in progress, 0 for none; §5.4), a close code that §7.4 refuses, 1007 for a
   close reason that isn't UTF-8 (§5.5.1, §8.1), 1009 for a data frame past [limit] bytes (§7.4.1); else {Fin, Opcode,
   Payload, Next}. *)
let client_frame ctx (a : t array) =
  let s = Native.text_arg ctx "parseFrame" a.(0) and at = Arrays.whole_index ctx a.(1) - 1 in
  let limit = Arrays.whole_index ctx a.(2) and kind = Arrays.whole_index ctx a.(3) in
  let code c = Trie.record code_keys [| Int c |] in
  if at < 0 || at > String.length s then Runtime.fail ctx Index (Messages.index_outside (at + 1) (String.length s));
  match length s at with
  | None -> Trie.record needs_keys [| Int (if String.length s - at < 2 then 2 else if Char.code s.[at + 1] land 127 = 126 then 4 else 10) |]
  | Some (n, p) ->
    let b0 = Char.code s.[at] and op = Char.code s.[at] land 15 in
    if b0 land 0x70 <> 0 || Char.code s.[at + 1] >= 128 || n < 0 || (op > 2 && op < 8) || op > 10
       || (op >= 8 && (b0 < 128 || n > 125)) || (op = 0 && kind = 0) || ((op = 1 || op = 2) && kind <> 0) then code 1002
    else if op < 8 && n > limit then code 1009
    else if String.length s < p + n then Trie.record needs_keys [| Int (p + n - at) |]
    else begin
      Runtime.build ctx ((n / 8) + 4);
      let payload = String.sub s p n in
      let close = if n >= 2 then String.get_uint16_be payload 0 else 0 in
      if op = 8 && (n = 1 || (n >= 2 && not (sendable close))) then code 1002
      else if op = 8 && n > 2 && not (String.is_valid_utf_8 (String.sub payload 2 (n - 2))) then code 1007
      else Trie.record frame_keys [| Value.of_bool (b0 >= 128); Int op; Text payload; Int (p + n + 1) |]
    end

(* A field of the connection that std/http hands over, {Read, Write, Arm} among them. *)
let field ctx io name =
  match Dict.get ctx "Accept" (Text name) io with
  | Some f -> f
  | None -> Runtime.fail ctx Field (Messages.no_field name)

let ok_text = function
  | Struct { shape = { sname = Some "Ok"; _ }; fields; _ } -> (match Trie.vget fields 0 with Text t -> Some t | _ -> None)
  | _ -> None

let refused = "\136\002\003\234"  (* a close frame of the code 1002 *)

(* The server side of a connection, once the response has gone: each message to [on_message], with a send that answers
   it, a pong for each ping, a close for a close, and 1002 for what it refuses. The idle deadline starts again at each
   message and each ping: an idle client doesn't hold its fiber forever. A buffer holds the frames read, the next one at
   [at], and is copied only when a read adds to it. *)
let serve ctx io rest on_message idle =
  let call name args = Compile.call_back ctx (field ctx io name) args in
  let write s = ignore (call "Write" [| Text s |]) in
  let send = Native.nat "send" 1 1 (fun ctx a -> Compile.call_back ctx (field ctx io "Write") [| Text (frame 1 (Native.text_arg ctx "send" a.(0)) "") |]) in
  let rec loop buffer at =
    match server_frame buffer at with
    | `More ->
      (match ok_text (call "Read" [||]) with
       | Some more when more <> "" -> loop (String.sub buffer at (String.length buffer - at) ^ more) 0
       | _ -> ())
    | `Frame (op, p, _) when op >= 8 && String.length p > 125 -> write refused
    | `Frame (8, p, _) -> write (frame 8 p "")
    | `Frame (op, p, next) when op = 9 || op = 1 || op = 2 ->
      Runtime.pay_bytes ctx (next - at);
      ignore (call "Arm" [| idle |]);
      if op = 9 then write (frame 10 p "") else ignore (Compile.call_back ctx on_message [| Text p; send |]);
      loop buffer next
    | `Frame (10, _, next) -> loop buffer next
    | `Frame _ | `Bad -> write refused
  in
  ignore (call "Arm" [| idle |]);
  loop rest 0;
  Missing

let accept_keys = Trie.names [| "Status"; "Body"; "Headers"; "Upgrade" |]
let header_keys = Trie.names [| "Name"; "Value" |]

let accept ctx (a : t array) =
  let key = Native.text_arg ctx "Accept" a.(0) and on_message = a.(1) in
  let idle = if Array.length a > 2 && a.(2) != Undef then a.(2) else Int default_idle in
  let header name v = Trie.record header_keys [| Text name; Text v |] in
  let upgrade = Native.nat "upgrade" 2 2 (fun ctx b -> serve ctx b.(0) (Native.text_arg ctx "upgrade" b.(1)) on_message idle) in
  Trie.record accept_keys
    [| Int 101; Text "";
       Arrays.list [| header "upgrade" "websocket"; header "connection" "Upgrade"; header "sec-websocket-accept" (answer key) |];
       upgrade |]

let natives =
  [ "Accept", Native.nat ~params:[| "key"; "onMessage"; "idle" |] "Accept" 2 3 accept;
    "DefaultIdle", Int default_idle;
    "MaxFrame", Int max_frame;
    (* Small names, which only std/websocket sees: its client. *)
    "frame", Native.nat "frame" 2 2 (fun ctx a ->
        let p = Native.text_arg ctx "frame" a.(1) in
        Runtime.build ctx ((String.length p / 8) + 4);
        Text (frame (Arrays.whole_index ctx a.(0)) p (random_bytes ctx 4)));
    "parseFrame", Native.nat "parseFrame" 4 4 client_frame;
    "newKey", Native.nat "newKey" 0 0 (fun ctx _ -> Text (base64 (random_bytes ctx 16)));
    "answer", Native.nat "answer" 1 1 (fun ctx a -> Text (answer (Native.text_arg ctx "answer" a.(0)))) ]
