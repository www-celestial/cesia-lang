(* The same bits on every system. On arm64, OCaml 5.5 compiles a float product that is an operand of an add or a sub into
   one instruction, fmadd, fmsub or fnmsub (asmcomp/arm64/selection.ml, lines 184-196 of its sources), which rounds once
   where x86-64 and WebAssembly round twice: x * x - 2.0 in a Cesia program gave other bits on a Mac. A product bound by
   a let is no operand. Without flambda, the let of a name is Strict (lambda/matching.ml, line 4246), which Simplif keeps
   (lambda/simplif.ml, line 578); Closure keeps a let of what is no constant (middle_end/closure/closure.ml, lines
   1020-1033); Cmm keeps it (asmcomp/cmmgen.ml, lines 1273 and 1289); and the selection computes it into a register first
   (asmcomp/selectgen.ml, lines 615-618): the add sees a variable. So this test reads each OCaml file of src/, super.ml as
   generated too, and fails on a product, *. or Float.mul, written as an operand of +., -., Float.add or Float.sub, or on
   a call there of a function of the same file whose result is a product, which OCaml inlines the same. Float.fma is the
   way to ask for one rounding. *)

open Parsetree

let rec bare e = match e.pexp_desc with Pexp_constraint (e, _) | Pexp_newtype (_, e) -> bare e | _ -> e
let named e = match (bare e).pexp_desc with Pexp_ident { txt; _ } -> Longident.flatten txt | _ -> []
let applied e = match (bare e).pexp_desc with Pexp_apply (f, args) -> (named f, List.length args) | _ -> ([], 0)
let is_mul e = match applied e with ([ "*." ] | [ "Float"; "mul" ] | [ "Stdlib"; "Float"; "mul" ]), 2 -> true | _ -> false
let is_add f = match named f with [ "+." ] | [ "-." ] | [ "Float"; ("add" | "sub") ] -> true | _ -> false

(* The functions whose body, past their parameters, is a product: names of this file only. *)
let rec result e =
  match (bare e).pexp_desc with Pexp_function (_, _, Pfunction_body b) -> result b | _ -> e

let check file =
  let ast = In_channel.with_open_text file (fun ic ->
      let lexbuf = Lexing.from_channel ic in
      Location.init lexbuf file;
      Parse.implementation lexbuf) in
  let products = Hashtbl.create 8 in
  let binding (it : Ast_iterator.iterator) (vb : value_binding) =
    (match vb.pvb_pat.ppat_desc, (bare vb.pvb_expr).pexp_desc with
     | Ppat_var { txt; _ }, Pexp_function _ when is_mul (result vb.pvb_expr) -> Hashtbl.replace products txt ()
     | _ -> ());
    Ast_iterator.default_iterator.value_binding it vb
  in
  let hits = ref [] in
  let expr (it : Ast_iterator.iterator) e =
    (match e.pexp_desc with
     | Pexp_apply (f, [ (_, a); (_, b) ]) when is_add f ->
       let fused x = is_mul x || (match applied x with [ n ], _ -> Hashtbl.mem products n | _ -> false) in
       if fused a || fused b then hits := e.pexp_loc :: !hits
     | _ -> ());
    Ast_iterator.default_iterator.expr it e
  in
  let it = { Ast_iterator.default_iterator with expr; value_binding = binding } in
  (* Twice: the first pass finds the functions, the second the calls, even those above the function. *)
  it.structure it ast;
  hits := [];
  it.structure it ast;
  List.rev !hits

let rec files dir =
  Sys.readdir dir |> Array.to_list |> List.sort compare
  |> List.concat_map (fun name ->
      let path = Filename.concat dir name in
      if name.[0] = '.' || name.[0] = '_' then []
      else if Sys.is_directory path then files path
      else if Filename.check_suffix name ".ml" || Filename.check_suffix name ".ml.in" then [ path ]
      else [])

let () =
  (* flambda's Un_anf puts a pure let used once back in its use (middle_end/flambda/un_anf.ml, lines 696-707): a product
     bound by a let would be fused again. *)
  if Config.flambda && Config.architecture = "arm64" then begin
    print_endline "fusion_test: this OCaml has flambda, which fuses again on arm64 the products bound by a let";
    exit 1
  end;
  let all = files "../src" in
  let hits = List.concat_map check all in
  List.iter
    (fun (l : Location.t) ->
       Printf.printf "%s:%d:%d: a product inside a + or a -: on arm64 one rounding instead of two; let-bind it\n"
         l.loc_start.pos_fname l.loc_start.pos_lnum (l.loc_start.pos_cnum - l.loc_start.pos_bol))
    hits;
  Printf.printf "fusion_test: %d OCaml files of src/, %d products inside a + or a -\n" (List.length all) (List.length hits);
  if hits <> [] then exit 1
