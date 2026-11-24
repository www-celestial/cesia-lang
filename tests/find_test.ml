(* The search for a part in a text, Native.find_from, against a plain one that compares the part at each byte. Two-Way,
   for the parts of 32 bytes or more, on every part of 1 to 4 bytes and every text of 0 to 11 over two letters, and of
   1 to 3 and 0 to 7 over three with fold, from every byte: its halves, periods and memory are all there in small. Then
   random parts of 1 to 72 bytes, through both searches: powers of a short unit with a tail, runs of one letter then
   another, over one to eight letters; on texts that hold them, hold them changed at one byte, or are runs of their unit
   changed at a few. Last, what a search of a long part allocates: a few words, not a table of its length.
   Usage: find_test.exe [CASES [SEED]], 2,000 random cases by default. *)
open Cesia

let failures = ref 0

let fail what =
  incr failures;
  if !failures <= 10 then prerr_endline ("FAILED: " ^ what)

(* Each place from each byte, by the plain search, against [find]. *)
let compare name find fold s part =
  let n = String.length s and m = String.length part in
  let low c = if fold then Char.lowercase_ascii c else c in
  let rec same j i = i >= m || (low s.[j + i] = low part.[i] && same j (i + 1)) in
  let next = ref (-1) in
  for from = n downto 0 do
    if from + m <= n && same from 0 then next := from;
    let got = find fold s part from in
    if got <> !next then fail (Printf.sprintf "%s of %S in %S from %d, fold %b: %d, not %d" name part s from fold got !next)
  done

(* Every word of [n] letters of [al]. *)
let words al n f =
  let b = Bytes.make n al.[0] in
  let rec go i = if i = n then f (Bytes.to_string b) else String.iter (fun c -> Bytes.set b i c; go (i + 1)) al in
  go 0

let every al fold parts texts =
  for m = 1 to parts do
    words al m (fun part -> for n = 0 to texts do words al n (fun s -> compare "find_long" Native.find_long fold s part) done)
  done

let random cases seed =
  let rng = Random.State.make [| seed |] in
  let int n = Random.State.int rng n in
  let alphabets = [| "ab"; "abc"; "aAbB"; "a"; "abcdefgh"; "\000\255a"; "aB" |] in
  for _ = 1 to cases do
    let al = alphabets.(int (Array.length alphabets)) in
    let letter () = al.[int (String.length al)] in
    let word k = String.init k (fun _ -> letter ()) in
    let unit = word (1 + int 5) in
    let run from k = String.init k (fun i -> unit.[(from + i) mod String.length unit]) in
    let m = if int 4 = 0 then 1 + int 31 else 32 + int 41 in
    let part =
      match int 4 with
      | 0 -> word m
      | 1 -> run 0 m ^ word (int 3)
      | 2 -> word (int 3) ^ run 0 m
      | _ -> String.make m al.[0] ^ word 1
    in
    let changed t ats =
      let t = Bytes.of_string t in
      List.iter (fun at -> if at >= 0 && at < Bytes.length t then Bytes.set t at (letter ())) ats;
      Bytes.to_string t
    in
    let s =
      match int 4 with
      | 0 -> word (int 200)
      | 1 -> word (int 100) ^ part ^ word (int 100) ^ if int 2 = 0 then part else ""
      | 2 -> changed (part ^ part ^ part) [ int (3 * String.length part) ]
      | _ -> let x = int 20 in changed (run (int 5) ((2 * m) + 20)) [ x; x + m - int 6; int ((2 * m) + 20) ]
    in
    let fold = int 2 = 0 in
    let part = if fold && int 2 = 0 then String.uppercase_ascii part else part in
    compare "find_from" (fun fold s part from -> Native.find_from ~fold s part from) fold s part
  done

(* The words a search allocates, folded or not, found or not: Knuth, Morris and Pratt took 8 bytes a byte of the part, a
   folded search a copy of it too. *)
let allocation () =
  let part = String.make 100_000 'a' ^ "b" in
  List.iter
    (fun (s, fold) ->
       let before = Gc.minor_words () +. (Gc.quick_stat ()).major_words -. (Gc.quick_stat ()).promoted_words in
       let at = Native.find_from ~fold s part 0 in
       let words = Gc.minor_words () +. (Gc.quick_stat ()).major_words -. (Gc.quick_stat ()).promoted_words -. before in
       if words > 200. then fail (Printf.sprintf "a search of %d bytes, fold %b, found at %d, allocated %.0f words" (String.length part) fold at words))
    [ String.make 200_000 'a', false; String.make 200_000 'A' ^ "B", true; String.make 50_000 'a' ^ part, false ]

let () =
  let cases = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 2_000 in
  let seed = if Array.length Sys.argv > 2 then int_of_string Sys.argv.(2) else 2026 in
  every "ab" false 4 11;
  every "aAb" true 3 7;
  random cases seed;
  allocation ();
  if !failures > 0 then begin
    Printf.eprintf "find_test: %d failures\n" !failures;
    exit 1
  end
