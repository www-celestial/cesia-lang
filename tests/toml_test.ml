(* The reader of kepler.toml: what it accepts, with its exact values, and what it refuses, with the line and the reason. *)
open Kepler

let failures = ref 0

let check name ok =
  if not ok then begin
    incr failures;
    prerr_endline ("FAILED: " ^ name)
  end

let table ?(start = 1) path entries = { Toml.path; start; entries }
let entry key value line = { Toml.key; value; line }
let accepted input expected = check (Printf.sprintf "%S" input) (Toml.parse input = Ok expected)

let refused input line reason =
  match Toml.parse input with
  | Error (l, r) -> check (Printf.sprintf "%S gave line %d: %s" input l r) (l = line && r = reason)
  | Ok _ -> check (Printf.sprintf "%S was accepted" input) false

let unsupported what = what ^ " aren't supported in this file."

let () =
  let open Toml in
  accepted "" [];
  accepted "a = \"x\"" [ table [] [ entry "a" (Text "x") 1 ] ];
  accepted "a-b_1 = false\n" [ table [] [ entry "a-b_1" (Flag false) 1 ] ];
  accepted "# c\r\n\r\n[t]\r\na = true # d\r\n" [ table ~start:3 [ "t" ] [ entry "a" (Flag true) 4 ] ];
  accepted "a = [\r\n 'x',\r\n]\r\nb = true\r\n" [ table [] [ entry "a" (Texts [ "x" ]) 1; entry "b" (Flag true) 4 ] ];
  accepted "[ a . b ]\nc = 'l\\n'\n" [ table [ "a"; "b" ] [ entry "c" (Text "l\\n") 2 ] ];
  accepted "a = \"\\\\ \\\" \\n \\t \\r\"\n" [ table [] [ entry "a" (Text "\\ \" \n \t \r") 1 ] ];
  accepted "a = [\n \"x\", # c\n 'y',\n]\nb = []\n"
    [ table [] [ entry "a" (Texts [ "x"; "y" ]) 1; entry "b" (Texts []) 5 ] ];
  accepted "a = \"é\"\n" [ table [] [ entry "a" (Text "é") 1 ] ];
  accepted "[a.b]\n[a]\nc = true\n" [ table [ "a"; "b" ] []; table ~start:2 [ "a" ] [ entry "c" (Flag true) 3 ] ];
  refused "\n\xff = 1" 2 "This line is not valid UTF-8.";
  refused "a = \"\x01\"\n" 1 "Control characters aren't allowed here.";
  refused "a = 'x'\r b = 'y'\n" 1 "Control characters aren't allowed here.";
  refused "a = true\r" 1 "Control characters aren't allowed here.";
  refused "a = true\nb = \x7f\n" 2 "Control characters aren't allowed here.";
  List.iter
    (fun v -> refused (Printf.sprintf "a = %s" v) 1 (unsupported "Numbers and dates"))
    [ "1"; "-1"; "+1"; "1.5"; "1979-05-27"; "nan"; "inf" ];
  refused "a = 'x'\r\nb = 1\r\n" 2 (unsupported "Numbers and dates");
  refused "a = {}" 1 (unsupported "Inline tables");
  refused "a = \"\"\"x\"\"\"" 1 (unsupported "Multi-line strings");
  refused "a = '''x'''" 1 (unsupported "Multi-line strings");
  refused "a = [\"\"\"x\"\"\"]" 1 (unsupported "Multi-line strings");
  refused "[[a]]" 1 (unsupported "Arrays of tables");
  refused "a.b = \"x\"" 1 (unsupported "Dotted keys");
  refused "\"a\" = \"x\"" 1 (unsupported "Quoted keys");
  refused "'a' = \"x\"" 1 (unsupported "Quoted keys");
  refused "[\"a\"]" 1 (unsupported "Quoted keys");
  refused "a = [[\"x\"]]" 1 (unsupported "Nested arrays");
  refused "a = [1]" 1 "Arrays hold strings only in this file.";
  refused "a = [true]" 1 "Arrays hold strings only in this file.";
  refused "a = [\"x\" \"y\"]" 1 "Expected a comma or ].";
  refused "a = \"x\" b" 1 "Expected the end of the line.";
  refused "a = true true" 1 "Expected the end of the line.";
  refused "[a] x" 1 "Expected the end of the line.";
  refused "a = \"x" 1 "This string is not closed.";
  refused "a = 'x" 1 "This string is not closed.";
  refused "a = \"x\ny\"" 1 "This string is not closed.";
  refused "a = \"x\\" 1 "This string is not closed.";
  refused "a = [\"x\"\n" 2 "This array is not closed.";
  refused "a = [" 1 "This array is not closed.";
  refused "a = \"\\b\"" 1 "The escape \\b isn't supported in this file.";
  refused "a = \"\\u0041\"" 1 "The escape \\u isn't supported in this file.";
  refused "= \"x\"" 1 "Expected a key.";
  refused "é = true" 1 "Expected a key.";
  refused "[]" 1 "Expected a key.";
  refused "[a.]" 1 "Expected a key.";
  refused "a \"x\"" 1 "Expected =.";
  refused "a =\n" 1 "Expected a value.";
  refused "a = truex" 1 "Expected a value.";
  refused "[a" 1 "Expected ].";
  refused "a = \"x\"\na = \"y\"\n" 2 "a is defined twice.";
  refused "[a]\n[a]\n" 2 "a is defined twice.";
  refused "[a]\nb = \"x\"\n[a.b]\n" 3 "a.b is defined twice.";
  refused "[a]\nb = \"x\"\n[a.b.c]\n" 3 "a.b is defined twice.";
  refused "[a.b]\n[a]\nb = \"x\"\n" 3 "a.b is defined twice.";
  refused "a = true\n[a]\n" 2 "a is defined twice.";
  refused "[a.b]\nc = true\n[a.b.c]\n" 3 "a.b.c is defined twice.";
  if !failures > 0 then exit 1;
  print_endline "toml_test: ok"
