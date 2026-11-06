(* Versions: how two compare, which are versions, and this Cesia against them. *)
open Cesia

let failures = ref 0

let check name ok =
  if not ok then begin
    incr failures;
    prerr_endline ("FAILED: " ^ name)
  end

let sign n = Int.compare n 0
let compares a b expected = check (Printf.sprintf "compare %S %S" a b) (sign (Version.compare a b) = expected)

let () =
  compares "0.2" "0.2.0" 0;
  compares "v0.10.0" "0.9.9" 1;
  compares "0.1.0" "0.2" (-1);
  compares "1" "0.99.99" 1;
  compares "0.3.0-nightly+62b49d8" "0.3" 0;
  compares "0.2.0+dev" "v0.2.0" 0;
  check "number" (Version.number = "0.3.0");
  check "text" (Version.text = "cesia " ^ Version.number ^ if Version.dev then "+dev" else "");
  check "at_least 0.1" (Version.at_least "0.1");
  check "at_least itself" (Version.at_least Version.number);
  check "not at_least 99" (not (Version.at_least "99"));
  List.iter (fun v -> check ("valid " ^ v) (Version.valid v)) [ "0.2"; "v1.10.0"; "3"; "0.3.0-nightly+62b49d8" ];
  List.iter (fun v -> check ("not valid " ^ v) (not (Version.valid v))) [ ""; "v"; "0..2"; "0.2."; "0.x"; "latest"; "-1" ];
  if !failures > 0 then exit 1;
  print_endline "version_test: ok"
