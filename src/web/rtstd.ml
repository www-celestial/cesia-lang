(* The natives of std/dict, std/text and std/json that a page needs, in WebAssembly, on the values of Rt: each one's
   checks and messages as the interpreter's (Native, Lists, Dict, Json), added to a module at its first use. What is
   easier said in Cesia, and fast enough so, is in the versions of packages of src/web/ (Pages). *)

open Wasm
open Rt

let init () = ()

(* The local of a parameter as a text, or the error of [name] that wants one. *)
let need_text rt name x site =
  [ Lget x; Test (false, T rt.bytes); If (Bnone, [], fail rt (Messages.need_text name a1) [ [ Lget x; call rt "describe" ] ] [ Lget site ]) ]

let bytes_of rt x = [ Lget x; Cast (false, T rt.bytes) ]

(* A map of the general form from a value that is a dictionary, or the error of [name]. *)
let () =
  def "as_dict" (fun rt -> [ v; nn rt.bytes; I32 ], [ nn rt.map ], fun _ ->
      [ Lget 0; call rt "as_map"; Lset 0;
        Lget 0; Test (false, T rt.map); If (Bnone, [ Lget 0; Cast (false, T rt.map); ret ], []);
        Lget 0; Test (false, T rt.recd);
        If (Bnone, fail rt (Messages.map_of_struct "\003" a2 |> fun (m : Messages.t) -> { m with text = replace m.text [ "\003", a1 ] })
                     [ [ Lget 1 ]; [ Lget 0; Cast (false, T rt.recd); struct_get rt.recd r_shape; struct_get rt.shape 0 ] ] [ Lget 2 ], []) ]
      @ fail rt (Messages.need_dict "\003" a2 |> fun (m : Messages.t) -> { m with text = replace m.text [ "\003", a1 ] })
        [ [ Lget 1 ]; [ Lget 0; call rt "describe" ] ] [ Lget 2 ]);
  (* A key: a number or a text, a float not NaN. *)
  def "check_key" (fun rt -> [ v; I32 ], [], fun _ ->
      [ Lget 0; Test (false, T rt.bytes); Lget 0; call rt "is_int"; i32_or; If (Bnone, [ ret ], []);
        Lget 0; Test (false, T rt.boxf); If (Bnone, [ Lget 0; call rt "float_of"; Lget 0; call rt "float_of"; f64_eq; If (Bnone, [ ret ], []) ], []) ]
      @ fail rt (Messages.dict_key a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
  def "empty_dict" (fun rt -> [], [ v ], fun _ ->
      [ I32 1; I32 0; array_new_default rt.vals; Rnull (T rt.i64s); I64 0L; struct_new rt.keys; I32 0; array_new_default rt.vals; I32 0; I32 1; struct_new rt.map ]);
  (* dict.Get, GetOr and Has: the place of the key, -1 when absent. GetOr's default, when it is given back, is shared, as
     the native shares an argument it returns: a write to it then copies, and leaves the variable it came from alone. *)
  def "dict_find" (fun rt -> [ v; v; nn rt.bytes; I32 ], [ I32 ], fun _ ->
      [ Lget 0; Lget 3; call rt "check_key"; Lget 1; Lget 2; Lget 3; call rt "as_dict"; Lget 0; call rt "map_find" ]);
  def "dict_get" (fun rt -> [ v; v; v; nn rt.bytes; I32 ], [ v ], fun fb ->
      let k = local fb I32 in
      [ Lget 0; Lget 2; Lget 3; Lget 4; call rt "dict_find"; Ltee k; I32 0; i32_lt_s; If (Bnone, [ Lget 1; call rt "share"; ret ], []);
        Lget 2; call rt "as_map"; Cast (false, T rt.map); struct_get rt.map m_vals; Lget k; array_get rt.vals; call rt "share" ]);
  (* dict.Put: a copy with the key set, the original as it was. *)
  def "dict_put" (fun rt -> [ v; v; v; I32 ], [ v ], fun _ ->
      [ Lget 0; Lget 3; call rt "check_key";
        Lget 2; text rt "Put"; Lget 3; call rt "as_dict"; call rt "map_copy"; Lget 0; Lget 1; call rt "share"; Lget 3; call rt "set_field" ]);
  (* dict.Drop: a new map without the key, its keys in their order. *)
  def "dict_drop" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let m = local fb (nn rt.map) and k = local fb I32 and n = local fb I32 and i = local fb I32 and j = local fb I32 in
      let names = local fb (nn rt.vals) and vals = local fb (nn rt.vals) in
      [ Lget 0; Lget 2; call rt "check_key"; Lget 1; text rt "Drop"; Lget 2; call rt "as_dict"; Lset m;
        Lget m; Lget 0; call rt "map_find"; Lset k;
        Lget k; I32 0; i32_lt_s; If (Bnone, [ Lget m; call rt "share"; ret ], []);
        Lget m; struct_get rt.map m_count; I32 1; i32_sub; Lset n;
        Lget n; array_new_default rt.vals; Lset names; Lget n; array_new_default rt.vals; Lset vals ]
      @ upto i n [ Lget i; Lget k; i32_ge_u; If (Bval I32, [ Lget i; I32 1; i32_add ], [ Lget i ]); Lset j;
                   Lget names; Lget i; Lget m; struct_get rt.map m_keys; struct_get rt.keys k_names; Lget j; array_get rt.vals; array_set rt.vals;
                   Lget vals; Lget i; Lget m; struct_get rt.map m_vals; Lget j; array_get rt.vals; call rt "share"; array_set rt.vals ]
      @ [ I32 1; Lget names; Lget n; Lget n; call rt "keys_of"; Lget vals; Lget n; I32 1; struct_new rt.map ]);
  (* dict.Keys, Values and Pairs: lists in the order of the keys. *)
  List.iter
    (fun (name, cell) ->
       def ("dict_" ^ name) (fun rt -> [ v; I32 ], [ v ], fun fb ->
           let m = local fb (nn rt.map) and n = local fb I32 and i = local fb I32 and w = local fb (nn rt.vals) in
           [ Lget 0; text rt name; Lget 1; call rt "as_dict"; Lset m; Lget m; struct_get rt.map m_count; Lset n;
             Lget n; array_new_default rt.vals; Lset w ]
           @ upto i n ([ Lget w; Lget i ]
                       @ cell rt [ Lget m; struct_get rt.map m_keys; struct_get rt.keys k_names; Lget i; array_get rt.vals ]
                           [ Lget m; struct_get rt.map m_vals; Lget i; array_get rt.vals; call rt "share" ]
                       @ [ array_set rt.vals ])
           @ [ I32 1; Lget n; Lget w; call rt "list_of" ]))
    [ "Keys", (fun _ k _ -> k); "Values", (fun _ _ x -> x);
      "Pairs", (fun rt k x -> [ I32 1; keys rt [| "Key"; "Value" |] ] @ k @ x @ [ array_new_fixed rt.vals 2; I32 2; I32 0; struct_new rt.map ]) ];
  (* dict.Dict(pairs): from {Key, Value} each, a later key in the place of the first. *)
  def "dict_of" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let m = local fb v and l = local fb (nn rt.list) and n = local fb I32 and i = local fb I32 and x = local fb v in
      let p = local fb (nl rt.map) and kk = local fb I32 and vk = local fb I32 in
      let bad e = fail rt (Messages.dict_pair a1) [ [ Lget e; call rt "describe" ] ] [ Lget 1 ] in
      [ call rt "empty_dict"; Lset m;
        Lget 0; ref_is_null; Lget 0; g_undef rt; ref_eq; i32_or; If (Bnone, [ Lget m; ret ], []);
        Lget 0; Test (false, T rt.list); If (Bnone, [], bad 0);
        Lget 0; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n ]
      @ upto i n [ Lget l; Lget i; call rt "elem"; Lset x;
                   Lget x; call rt "as_map"; Test (false, T rt.map); If (Bnone, [], bad x);
                   Lget x; call rt "as_map"; Cast (false, T rt.map); Lset p;
                   Lget p; as_non_null; text rt "Key"; call rt "map_find"; Lset kk; Lget p; as_non_null; text rt "Value"; call rt "map_find"; Lset vk;
                   Lget kk; I32 0; i32_lt_s; Lget vk; I32 0; i32_lt_s; i32_or; If (Bnone, bad x, []);
                   Lget p; struct_get rt.map m_vals; Lget kk; array_get rt.vals; Lget 1; call rt "check_key";
                   Lget m; Lget p; struct_get rt.map m_vals; Lget kk; array_get rt.vals;
                   Lget p; struct_get rt.map m_vals; Lget vk; array_get rt.vals; call rt "share"; Lget 1; call rt "set_field"; Lset m ]
      @ [ Lget m ])

(* Texts. *)
let () =
  def "byte_length" (fun rt -> [ v; I32 ], [ v ], fun _ -> need_text rt "ByteLength" 0 1 @ bytes_of rt 0 @ [ array_len; ref_i31 ]);
  (* A byte's place, from 1, inside the text. *)
  def "byte_at" (fun rt -> [ I64; nn rt.bytes; I32 ], [], fun _ ->
      [ Lget 0; i64 1; i64_lt_s; Lget 0; Lget 1; array_len; i64_extend_u; i64_gt_s; i32_or;
        If (Bnone, fail ~kind:k_index rt (Messages.text_outside 1000001 1000002 "bytes" |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
                     [ [ Lget 0; call rt "itoa" ]; [ Lget 1; array_len; i64_extend_u; call rt "itoa" ] ] [ Lget 2 ], []) ]);
  def "byte" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let i = local fb I64 in
      [ Lget 0; Lget 2; call rt "whole"; Lset i ] @ need_text rt "Byte" 1 2
      @ [ Lget i ] @ bytes_of rt 1 @ [ Lget 2; call rt "byte_at" ] @ bytes_of rt 1 @ [ Lget i; i32_wrap; I32 1; i32_sub; array_get_u rt.bytes; ref_i31 ]);
  (* The bytes from [a] for [n], a new text. *)
  def "sub" (fun rt -> [ nn rt.bytes; I32; I32 ], [ nn rt.bytes ], fun fb ->
      let r = local fb (nn rt.bytes) in
      [ Lget 2; array_new_default rt.bytes; Lset r; Lget r; I32 0; Lget 0; Lget 1; Lget 2; array_copy rt.bytes rt.bytes; Lget r ]);
  def "byte_slice" (fun rt -> [ v; v; v; I32 ], [ v ], fun fb ->
      let a = local fb I64 and b = local fb I64 in
      [ Lget 0; Lget 3; call rt "whole"; Lset a; Lget 1; Lget 3; call rt "whole"; Lset b ] @ need_text rt "ByteSlice" 2 3
      @ [ Lget b; Lget a; i64_lt_s; If (Bnone, [ I32 0; array_new_default rt.bytes; ret ], []);
          Lget a ] @ bytes_of rt 2 @ [ Lget 3; call rt "byte_at"; Lget b ] @ bytes_of rt 2 @ [ Lget 3; call rt "byte_at" ]
      @ bytes_of rt 2 @ [ Lget a; i32_wrap; I32 1; i32_sub; Lget b; Lget a; i64_sub; i32_wrap; I32 1; i32_add; call rt "sub" ]);
  (* The first place, from 0, of [p] in [s] at [from] or after, or -1. *)
  def "find_bytes" (fun rt -> [ nn rt.bytes; nn rt.bytes; I32 ], [ I32 ], fun fb ->
      let i = local fb I32 and j = local fb I32 and n = local fb I32 and m = local fb I32 in
      [ Lget 0; array_len; Lset m; Lget 1; array_len; Lget m; i32_sub; Lset n; Lget 2; Lset i;
        Block (Bnone, [ Loop (Bnone, [
            Lget i; Lget n; i32_gt_s; Br_if 1;
            I32 0; Lset j;
            Block (Bnone, [ Loop (Bnone, [
                Lget j; Lget m; i32_ge_u; Br_if 1;
                Lget 1; Lget i; Lget j; i32_add; array_get_u rt.bytes; Lget 0; Lget j; array_get_u rt.bytes; i32_ne; Br_if 1;
                Lget j; I32 1; i32_add; Lset j; Br 0 ]) ]);
            Lget j; Lget m; i32_eq; If (Bnone, [ Lget i; ret ], []);
            Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
        I32 (-1) ]);
  def "byte_find" (fun rt -> [ v; v; v; I32 ], [ v ], fun fb ->
      let from = local fb I64 and at = local fb I32 in
      need_text rt "ByteFind" 0 3 @ [ Lget 1; Lget 3; call rt "whole"; Lset from ] @ need_text rt "ByteFind" 2 3
      @ bytes_of rt 0 @ [ array_len; i32_eqz; If (Bnone, [ Lget from; call rt "box_i"; ret ], []);
          Lget from; i64 1; i64_lt_s; Lget from ] @ bytes_of rt 2 @ [ array_len; i64_extend_u; i64_gt_s; i32_or; If (Bnone, [ missing; ret ], []) ]
      @ bytes_of rt 0 @ bytes_of rt 2 @ [ Lget from; i32_wrap; I32 1; i32_sub; call rt "find_bytes"; Ltee at;
          I32 0; i32_lt_s; If (Bval v, [ missing ], [ Lget at; I32 1; i32_add; ref_i31 ]) ]);
  (* StartsWith, EndsWith and Contains. *)
  List.iter
    (fun name ->
       def ("text_" ^ name) (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
           let i = local fb I32 and n = local fb I32 and off = local fb I32 in
           need_text rt name 0 2 @ need_text rt name 1 2
           @ (if name = "Contains" then
                bytes_of rt 0 @ bytes_of rt 1 @ [ I32 0; call rt "find_bytes"; I32 0; i32_ge_s ] @ bool_of rt
              else
                bytes_of rt 0 @ [ array_len; Lset n ] @ bytes_of rt 1 @ [ array_len; Lget n; i32_lt_u; If (Bnone, [ g_false rt; ret ], []) ]
                @ (if name = "EndsWith" then bytes_of rt 1 @ [ array_len; Lget n; i32_sub; Lset off ] else [])
                @ upto i n (bytes_of rt 0 @ [ Lget i; array_get_u rt.bytes ] @ bytes_of rt 1 @ [ Lget i; Lget off; i32_add; array_get_u rt.bytes; i32_ne;
                                                                                             If (Bnone, [ g_false rt; ret ], []) ])
                @ [ g_true rt ])))
    [ "StartsWith"; "EndsWith"; "Contains" ];
  (* text.Join: each element as text.Text writes it, a text as it is. *)
  def "join" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let b = local fb (nn rt.buf) and l = local fb (nn rt.list) and n = local fb I32 and i = local fb I32 in
      need_text rt "Join" 0 2
      @ [ Lget 1; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_array "Join" a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
          Lget 1; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n; call rt "buf_new"; Lset b ]
      @ upto i n ([ Lget i; If (Bnone, [ Lget b ] @ bytes_of rt 0 @ [ call rt "buf_add" ], []);
                    Lget b; Lget l; Lget i; call rt "elem"; call rt "text_of"; call rt "buf_add" ])
      @ [ Lget b; call rt "buf_done" ]);
  (* The length of the character of UTF-8 that starts with byte c: 1 for a byte that continues one or isn't UTF-8. *)
  def "char_len" (fun _ -> [ I32 ], [ I32 ], fun _ ->
      [ Lget 0; I32 0xf0; i32_ge_u; If (Bnone, [ I32 4; ret ], []);
        Lget 0; I32 0xe0; i32_ge_u; If (Bnone, [ I32 3; ret ], []);
        Lget 0; I32 0xc0; i32_ge_u; If (Bval I32, [ I32 2 ], [ I32 1 ]) ]);
  (* The byte, from 0, where character k, from 0, starts, or the length past the last. *)
  def "char_byte" (fun rt -> [ nn rt.bytes; I32 ], [ I32 ], fun fb ->
      let i = local fb I32 and c = local fb I32 in
      [ Block (Bnone, [ Loop (Bnone, [
            Lget i; Lget 0; array_len; i32_ge_u; Br_if 1;
            Lget 0; Lget i; array_get_u rt.bytes; I32 0xc0; i32_and; I32 0x80; i32_ne;
            If (Bnone, [ Lget c; Lget 1; i32_eq; Br_if 2; Lget c; I32 1; i32_add; Lset c ], []);
            Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
        Lget i ]);
  def "chars" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let s = local fb (nn rt.bytes) and out = local fb (nn rt.list) and i = local fb I32 and j = local fb I32 in
      need_text rt "Chars" 0 1
      @ bytes_of rt 0 @ [ Lset s; call rt "builder"; Lset out;
          Block (Bnone, [ Loop (Bnone, [
              Lget i; Lget s; array_len; i32_ge_u; Br_if 1;
              Lget i; I32 1; i32_add; Lset j;
              Block (Bnone, [ Loop (Bnone, [ Lget j; Lget s; array_len; i32_ge_u; Br_if 1; Lget s; Lget j; array_get_u rt.bytes; I32 0xc0; i32_and; I32 0x80; i32_ne; Br_if 1;
                                             Lget j; I32 1; i32_add; Lset j; Br 0 ]) ]);
              Lget out; Lget s; Lget i; Lget j; Lget i; i32_sub; call rt "sub"; call rt "push"; Lget j; Lset i; Br 0 ]) ]);
          Lget out; call rt "built" ]);
  (* text.Slice and Find, in characters. *)
  def "text_slice" (fun rt -> [ v; v; v; I32 ], [ v ], fun fb ->
      let a = local fb I64 and b = local fb I64 and n = local fb I32 and s = local fb (nn rt.bytes) and x = local fb I32 in
      let outside l = fail ~kind:k_index rt (Messages.text_outside 1000001 1000002 "characters" |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
          [ [ Lget l; call rt "itoa" ]; [ Lget n; i64_extend_u; call rt "itoa" ] ] [ Lget 3 ] in
      [ Lget 0; Lget 3; call rt "whole"; Lset a; Lget 1; Lget 3; call rt "whole"; Lset b ] @ need_text rt "Slice" 2 3
      @ bytes_of rt 2 @ [ Lset s; Lget s; call rt "code_points"; Lset n;
          Lget a; i64 1; i64_lt_s; If (Bnone, outside a, []);
          Lget b; Lget n; i64_extend_u; i64_gt_s; If (Bnone, outside b, []);
          Lget b; Lget a; i64_lt_s; If (Bnone, [ I32 0; array_new_default rt.bytes; ret ], []);
          Lget s; Lget a; i32_wrap; I32 1; i32_sub; call rt "char_byte"; Lset x;
          Lget s; Lget x; Lget s; Lget b; i32_wrap; call rt "char_byte"; Lget x; i32_sub; call rt "sub" ]);
  def "text_find" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let at = local fb I32 in
      need_text rt "Find" 0 2 @ need_text rt "Find" 1 2
      @ bytes_of rt 0 @ bytes_of rt 1 @ [ I32 0; call rt "find_bytes"; Ltee at; I32 0; i32_lt_s; If (Bnone, [ missing; ret ], []) ]
      @ bytes_of rt 1 @ [ I32 0; Lget at; call rt "sub"; call rt "code_points"; I32 1; i32_add; ref_i31 ]);
  def "text_code" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let s = local fb (nn rt.bytes) and c = local fb I32 and i = local fb I32 and n = local fb I32 in
      need_text rt "Code" 0 1
      @ bytes_of rt 0 @ [ Lset s; Lget s; array_len; i32_eqz; If (Bnone, fail rt (Messages.empty_text "Code") [] [ Lget 1 ], []);
          Lget s; I32 0; array_get_u rt.bytes; Lset c; Lget c; call rt "char_len"; Lset n;
          Lget n; I32 1; i32_gt_u; If (Bnone, [ Lget c; I32 0xff; Lget n; I32 1; i32_add; Op 0x76 (* shr_u *); i32_and; Lset c ], []);
          I32 1; Lset i ]
      @ [ Block (Bnone, [ Loop (Bnone, [ Lget i; Lget n; i32_ge_u; Br_if 1; Lget i; Lget s; array_len; i32_ge_u; Br_if 1;
                                       Lget c; I32 6; Op 0x74 (* shl *); Lget s; Lget i; array_get_u rt.bytes; I32 0x3f; i32_and; i32_or; Lset c;
                                       Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
          Lget c; ref_i31 ]);
  (* text.Char: the UTF-8 of a code point. *)
  def "text_char" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let c = local fb I32 and b = local fb (nn rt.buf) in
      let byte e = [ Lget b ] @ e @ [ call rt "buf_byte" ] in
      [ Lget 0; call rt "is_int"; If (Bval I32, [ Lget 0; call rt "int_of"; i64 0; i64_ge_s; Lget 0; call rt "int_of"; i64 0x10ffff; i64_le_s; i32_and ], [ I32 0 ]);
        If (Bnone, [], fail rt (Messages.bad_char a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 1 ]);
        Lget 0; call rt "int_of"; i32_wrap; Lset c; call rt "buf_new"; Lset b;
        Lget c; I32 0x80; i32_lt_u;
        If (Bnone, byte [ Lget c ],
            [ Lget c; I32 0x800; i32_lt_u;
              If (Bnone, byte [ Lget c; I32 6; Op 0x76; I32 0xc0; i32_or ] @ byte [ Lget c; I32 0x3f; i32_and; I32 0x80; i32_or ],
                  [ Lget c; I32 0x10000; i32_lt_u;
                    If (Bnone, byte [ Lget c; I32 12; Op 0x76; I32 0xe0; i32_or ] @ byte [ Lget c; I32 6; Op 0x76; I32 0x3f; i32_and; I32 0x80; i32_or ]
                               @ byte [ Lget c; I32 0x3f; i32_and; I32 0x80; i32_or ],
                        byte [ Lget c; I32 18; Op 0x76; I32 0xf0; i32_or ] @ byte [ Lget c; I32 12; Op 0x76; I32 0x3f; i32_and; I32 0x80; i32_or ]
                        @ byte [ Lget c; I32 6; Op 0x76; I32 0x3f; i32_and; I32 0x80; i32_or ] @ byte [ Lget c; I32 0x3f; i32_and; I32 0x80; i32_or ]) ]) ]);
        Lget b; call rt "buf_done" ]);
  (* text.Trim: spaces, tabs, line ends and form feeds off both ends. *)
  def "trim" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let s = local fb (nn rt.bytes) and a = local fb I32 and b = local fb I32 and c = local fb I32 in
      let space i = [ Lget s; Lget i; array_get_u rt.bytes; Lset c;
                      Lget c; I32 32; i32_eq; Lget c; I32 12; i32_eq; i32_or; Lget c; I32 10; i32_eq; i32_or; Lget c; I32 13; i32_eq; i32_or; Lget c; I32 9; i32_eq; i32_or ] in
      need_text rt "Trim" 0 1
      @ bytes_of rt 0 @ [ Lset s; Lget s; array_len; Lset b;
          Block (Bnone, [ Loop (Bnone, [ Lget a; Lget b; i32_ge_u; Br_if 1 ] @ space a @ [ i32_eqz; Br_if 1; Lget a; I32 1; i32_add; Lset a; Br 0 ]) ]);
          Block (Bnone, [ Loop (Bnone, [ Lget b; Lget a; i32_le_u; Br_if 1; Lget b; I32 1; i32_sub; Lset b ] @ space b
                                       @ [ i32_eqz; If (Bnone, [ Lget b; I32 1; i32_add; Lset b; Br 2 ], []); Br 0 ]) ]);
          Lget a; i32_eqz; Lget b; Lget s; array_len; i32_eq; i32_and; If (Bnone, [ Lget 0; ret ], []);
          Lget s; Lget a; Lget b; Lget a; i32_sub; call rt "sub" ]);
  (* text.Lower and Upper, of ASCII letters. *)
  List.iter
    (fun (name, lo, hi, d) ->
       def ("text_" ^ name) (fun rt -> [ v; I32 ], [ v ], fun fb ->
           let s = local fb (nn rt.bytes) and r = local fb (nn rt.bytes) and i = local fb I32 and c = local fb I32 in
           need_text rt name 0 1
           @ bytes_of rt 0 @ [ Lset s; Lget s; I32 0; Lget s; array_len; call rt "sub"; Lset r ]
           @ [ Block (Bnone, [ Loop (Bnone, [ Lget i; Lget s; array_len; i32_ge_u; Br_if 1;
                                             Lget s; Lget i; array_get_u rt.bytes; Lset c;
                                             Lget c; I32 lo; i32_ge_u; Lget c; I32 hi; i32_le_u; i32_and;
                                             If (Bnone, [ Lget r; Lget i; Lget c; I32 d; i32_add; array_set rt.bytes ], []);
                                             Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
               Lget r ]))
    [ "Lower", 65, 90, 32; "Upper", 97, 122, -32 ];
  def "repeat" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let n = local fb I64 and b = local fb (nn rt.buf) and i = local fb I64 in
      [ Lget 0; Lget 2; text rt "Repeat"; call rt "count_arg"; i64_extend_u; Lset n ] @ need_text rt "Repeat" 1 2
      @ [ call rt "buf_new"; Lset b;
          Block (Bnone, [ Loop (Bnone, [ Lget i; Lget n; i64_ge_s; Br_if 1; Lget b ] @ bytes_of rt 1 @ [ call rt "buf_add"; Lget i; i64 1; i64_add; Lset i; Br 0 ]) ]);
          Lget b; call rt "buf_done" ]);
  (* text.Split and Replace: the pieces between the occurrences of a separator that isn't empty. *)
  def "split" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let at = local fb I32 and from = local fb I32 and out = local fb (nn rt.list) and m = local fb I32 in
      need_text rt "Split" 0 2 @ need_text rt "Split" 1 2
      @ bytes_of rt 0 @ [ array_len; Ltee m; i32_eqz; If (Bnone, fail rt (Messages.empty_text "Split") [] [ Lget 2 ], []);
          call rt "builder"; Lset out;
          Block (Bnone, [ Loop (Bnone, bytes_of rt 0 @ bytes_of rt 1 @ [ Lget from; call rt "find_bytes"; Lset at; Lget at; I32 0; i32_lt_s; Br_if 1;
                                       Lget out ] @ bytes_of rt 1 @ [ Lget from; Lget at; Lget from; i32_sub; call rt "sub"; call rt "push";
                                       Lget at; Lget m; i32_add; Lset from; Br 0 ]) ]);
          Lget out ] @ bytes_of rt 1 @ [ Lget from ] @ bytes_of rt 1 @ [ array_len; Lget from; i32_sub; call rt "sub"; call rt "push";
          Lget out; call rt "built" ]);
  def "replace" (fun rt -> [ v; v; v; I32 ], [ v ], fun fb ->
      let at = local fb I32 and from = local fb I32 and b = local fb (nn rt.buf) and m = local fb I32 in
      need_text rt "Replace" 0 3 @ need_text rt "Replace" 1 3 @ need_text rt "Replace" 2 3
      @ bytes_of rt 0 @ [ array_len; Ltee m; i32_eqz; If (Bnone, fail rt (Messages.empty_text "Replace") [] [ Lget 3 ], []);
          call rt "buf_new"; Lset b;
          Block (Bnone, [ Loop (Bnone, bytes_of rt 0 @ bytes_of rt 2 @ [ Lget from; call rt "find_bytes"; Lset at; Lget at; I32 0; i32_lt_s; Br_if 1;
                                       Lget b ] @ bytes_of rt 2 @ [ Lget from; Lget at; Lget from; i32_sub; call rt "sub"; call rt "buf_add";
                                       Lget b ] @ bytes_of rt 1 @ [ call rt "buf_add";
                                       Lget at; Lget m; i32_add; Lset from; Br 0 ]) ]);
          Lget b ] @ bytes_of rt 2 @ [ Lget from ] @ bytes_of rt 2 @ [ array_len; Lget from; i32_sub; call rt "sub"; call rt "buf_add";
          Lget b; call rt "buf_done" ]);
  (* text.FromNumbers: the bytes of numbers, little-endian, as a binary file keeps them. *)
  def "from_numbers" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let kind = local fb I32 and size = local fb I32 and l = local fb (nn rt.list) and n = local fb I32 and r = local fb (nn rt.bytes) in
      let i = local fb I32 and x = local fb I64 and k = local fb I32 and f = local fb F64 in
      let kinds = [ "u8", 1; "i8", 1; "u16", 2; "i16", 2; "u32", 4; "i32", 4; "f32", 4; "f64", 8 ] in
      need_text rt "FromNumbers" 0 2
      @ List.concat (List.mapi (fun j (name, sz) -> [ Lget 0; Cast (false, T rt.bytes); text rt name; call rt "bytes_eq"; If (Bnone, [ I32 (j + 1); Lset kind; I32 sz; Lset size ], []) ]) kinds)
      @ [ Lget kind; i32_eqz; If (Bnone, fail rt (Messages.number_kind "FromNumbers" a1) [ bytes_of rt 0 ] [ Lget 2 ], []);
          Lget 1; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.need_array "FromNumbers" a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
          Lget 1; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n;
          Lget n; Lget size; i32_mul; array_new_default rt.bytes; Lset r ]
      @ upto i n [ Lget kind; I32 7; i32_ge_u;
                   If (Bnone, [ Lget l; Lget i; call rt "elem"; call rt "as_float"; Lset f;
                                Lget kind; I32 7; i32_eq;
                                If (Bval I64, [ Lget f; Op 0xb6 (* f32.demote_f64 *); Op 0xbc (* i32.reinterpret_f32 *); i64_extend_u ], [ Lget f; Op 0xbd (* i64.reinterpret_f64 *) ]); Lset x ],
                       [ Lget l; Lget i; call rt "elem"; call rt "as_int"; Lset x ]);
                   I32 0; Lset k;
                   Block (Bnone, [ Loop (Bnone, [ Lget k; Lget size; i32_ge_u; Br_if 1;
                                                  Lget r; Lget i; Lget size; i32_mul; Lget k; i32_add; Lget x; i32_wrap; array_set rt.bytes;
                                                  Lget x; i64 8; i64_shr_u; Lset x; Lget k; I32 1; i32_add; Lset k; Br 0 ]) ]) ]
      @ [ Lget r ])

(* json.Text: JSON on one line, as Json.write: a dictionary's keys and a struct's public fields as members, an array as a
   list, texts escaped; nan, an infinite float, a function, a text that isn't UTF-8 are errors (the last isn't checked
   here: the bytes go as they are). *)
let () =
  def "json_text" (fun rt -> [ nn rt.buf; nn rt.bytes ], [], fun fb ->
      let i = local fb I32 and c = local fb I32 and n = local fb I32 in
      let byte e = [ Lget 0 ] @ e @ [ call rt "buf_byte" ] in
      [ Lget 1; array_len; Lset n ] @ byte [ I32 34 ]
      @ upto i n ([ Lget 1; Lget i; array_get_u rt.bytes; Lset c;
                    Lget c; I32 34; i32_eq; Lget c; I32 92; i32_eq; i32_or;
                    If (Bnone, byte [ I32 92 ] @ byte [ Lget c ],
                        [ Lget c; I32 32; i32_lt_u;
                          If (Bnone, byte [ I32 92 ]
                                     @ [ Lget c; I32 10; i32_eq; If (Bnone, byte [ I32 110 ],
                                         [ Lget c; I32 9; i32_eq; If (Bnone, byte [ I32 116 ],
                                           [ Lget c; I32 13; i32_eq; If (Bnone, byte [ I32 114 ],
                                             byte [ I32 117 ] @ byte [ I32 48 ] @ byte [ I32 48 ] @ byte [ Lget c; I32 4; Op 0x76; I32 48; i32_add ]
                                             @ byte [ Lget c; I32 15; i32_and; Ltee c; I32 10; i32_lt_u; If (Bval I32, [ Lget c; I32 48; i32_add ], [ Lget c; I32 87; i32_add ]) ]) ]) ]) ],
                              byte [ Lget c ]) ]) ])
      @ byte [ I32 34 ]);
  def "json" (fun rt -> [ nn rt.buf; v; I32; I32 ], [], fun fb ->
      let x = 1 and site = 2 in
      let add s = [ Lget 0; text rt s; call rt "buf_add" ] in
      let byte c = [ Lget 0; I32 (Char.code c); call rt "buf_byte" ] in
      let l = local fb (nl rt.list) and n = local fb I32 and k = local fb I32 and mp = local fb (nl rt.map) and rc = local fb (nl rt.recd) and f = local fb F64 in
      let first = local fb I32 and name = local fb (nn rt.bytes) in
      let sub e = [ Lget 0 ] @ e @ [ Lget site; Lget 3; I32 1; i32_add; call rt "json" ] in
      let bad = fail rt (Messages.json_value a1) [ [ Lget x; call rt "describe" ] ] [ Lget site ] in
      [ Lget 3; I32 1000; i32_gt_u; If (Bnone, fail rt (Messages.json_nested 1000) [] [ Lget site ], []);
        Lget x; ref_is_null; If (Bnone, add "null" @ [ ret ], []);
        Lget x; call rt "as_map"; Lset x;
        Lget x; g_true rt; ref_eq; If (Bnone, add "true" @ [ ret ], []);
        Lget x; g_false rt; ref_eq; If (Bnone, add "false" @ [ ret ], []);
        Lget x; call rt "is_int"; If (Bnone, [ Lget 0; Lget x; call rt "int_of"; call rt "write_int"; ret ], []);
        Lget x; Test (false, T rt.boxf);
        If (Bnone, [ Lget x; call rt "float_of"; Lset f; Lget f; Lget f; f64_ne; Lget f; f64_abs; F64 infinity; f64_eq; i32_or; If (Bnone, bad, []);
                     Lget 0; Lget f; call rt "write_float"; ret ], []);
        Lget x; Test (false, T rt.bytes); If (Bnone, [ Lget 0; Lget x; Cast (false, T rt.bytes); call rt "json_text"; ret ], []);
        Lget x; Test (false, T rt.list);
        If (Bnone, [ Lget x; Cast (false, T rt.list); Lset l; Lget l; as_non_null; call rt "cells"; Lset n ] @ byte '['
                   @ upto k n ([ Lget k; If (Bnone, byte ',', []) ] @ sub [ Lget l; as_non_null; Lget k; call rt "elem" ])
                   @ byte ']' @ [ ret ], []);
        Lget x; Test (false, T rt.map);
        If (Bnone, [ Lget x; Cast (false, T rt.map); Lset mp; Lget mp; struct_get rt.map m_count; Lset n ] @ byte '{'
                   @ upto k n ([ Lget k; If (Bnone, byte ',', []);
                                 Lget 0; Lget mp; struct_get rt.map m_keys; struct_get rt.keys k_names; Lget k; array_get rt.vals; call rt "text_of"; call rt "json_text" ]
                               @ byte ':' @ sub [ Lget mp; struct_get rt.map m_vals; Lget k; array_get rt.vals ])
                   @ byte '}' @ [ ret ], []);
        (* A struct: its public fields, the names of a capital first letter. *)
        Lget x; Test (false, T rt.recd);
        If (Bnone, [ Lget x; Cast (false, T rt.recd); Lset rc; Lget rc; struct_get rt.recd r_fields; array_len; Lset n; I32 1; Lset first ] @ byte '{'
                   @ upto k n [ Lget rc; struct_get rt.recd r_shape; struct_get rt.shape 1; Lget k; array_get rt.vals; Cast (false, T rt.bytes); Lset name;
                                Lget name; array_len; If (Bval I32, [ Lget name; I32 0; array_get_u rt.bytes; I32 65; i32_sub; I32 26; i32_lt_u ], [ I32 0 ]);
                                If (Bnone, [ Lget first; i32_eqz; If (Bnone, byte ',', []); I32 0; Lset first; Lget 0; Lget name; call rt "json_text" ]
                                           @ byte ':' @ sub [ Lget rc; struct_get rt.recd r_fields; Lget k; array_get rt.vals ], []) ]
                   @ byte '}' @ [ ret ], []) ]
      @ bad);
  def "json_of" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let b = local fb (nn rt.buf) in
      [ call rt "buf_new"; Lset b; Lget b; Lget 0; Lget 1; I32 0; call rt "json"; Lget b; call rt "buf_done" ])


(* Indexes past one whole number, as Arrays.positions, read1 and read2. An index of a dimension is a kind and its
   operands: 0 a whole number [lo], 1 a slice [lo]..[hi], 3 a value [m], a mask of booleans when it is a list, else a
   whole number. *)
let outside rt e n site =
  fail ~kind:k_index rt (Messages.index_outside 1000001 1000002 |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
    [ e @ [ call rt "itoa" ]; [ Lget n; i64_extend_u; call rt "itoa" ] ] [ Lget site ]

(* Messages.index_outside2 of four numbers: two operands, each two numbers and the words of the message between them. *)
let outside2 rt i j r c site =
  let t = (Messages.index_outside2 1000001 1000002 1000003 1000004).text in
  let at x =
    let d = string_of_int x in
    let k = ref 0 in
    while String.sub t !k 7 <> d do incr k done;
    !k
  in
  let a = at 1000001 and b = at 1000002 and c' = at 1000003 and d = at 1000004 in
  let piece x y = String.sub t (x + 7) (y - x - 7) in
  let m = Messages.plain (String.sub t 0 a ^ a1 ^ piece b c' ^ a2 ^ String.sub t (d + 7) (String.length t - d - 7)) in
  let two x y sep = x @ [ call rt "itoa"; text rt sep ] @ y @ [ call rt "itoa"; call rt "cat3" ] in
  fail ~kind:k_index rt m [ two i j (piece a b); two r c (piece c' d) ] [ Lget site ]

let () =
  (* Three texts end to end. *)
  def "cat3" (fun rt -> [ nn rt.bytes; nn rt.bytes; nn rt.bytes ], [ nn rt.bytes ], fun fb ->
      let b = local fb (nn rt.buf) in
      [ call rt "buf_new"; Lset b; Lget b; Lget 0; call rt "buf_add"; Lget b; Lget 1; call rt "buf_add"; Lget b; Lget 2; call rt "buf_add"; Lget b; call rt "buf_done" ]);
  (* The positions, from 0, that an index selects in a dimension of size n. *)
  def "positions" (fun rt -> [ I32; I64; I64; v; I32; I32 ], [ nn rt.i32s ], fun fb ->
      let kind = 0 and lo = 1 and hi = 2 and m = 3 and n = 4 and site = 5 in
      let out = local fb (nn rt.i32s) and k = local fb I32 and used = local fb I32 and l = local fb (nn rt.list) and x = local fb v in
      let w = local fb (nn rt.i32s) in
      [ Lget kind; I32 3; i32_eq;
        If (Bnone, [ Lget m; Test (false, T rt.list); If (Bval I32, [ I32 2 ], [ Lget m; Lget site; call rt "whole"; Lset lo; I32 0 ]); Lset kind ], []);
        Lget kind; i32_eqz;
        If (Bnone, [ Lget lo; i64 1; i64_lt_s; Lget lo; Lget n; i64_extend_u; i64_gt_s; i32_or ]
                   @ [ If (Bnone, outside rt [ Lget lo ] n site, []); Lget lo; i32_wrap; I32 1; i32_sub; array_new_fixed rt.i32s 1; ret ], []);
        Lget kind; I32 1; i32_eq;
        If (Bnone, [ Lget lo; Lget hi; i64_gt_s; If (Bnone, [ I32 0; array_new_default rt.i32s; ret ], []);
                     Lget lo; i64 1; i64_lt_s; If (Bnone, outside rt [ Lget lo ] n site, []);
                     Lget hi; Lget n; i64_extend_u; i64_gt_s; If (Bnone, outside rt [ Lget hi ] n site, []);
                     Lget hi; Lget lo; i64_sub; i32_wrap; I32 1; i32_add; Lset used; Lget used; array_new_default rt.i32s; Lset out ]
                   @ upto k used [ Lget out; Lget k; Lget lo; i32_wrap; I32 1; i32_sub; Lget k; i32_add; array_set rt.i32s ]
                   @ [ Lget out; ret ], []);
        (* A mask: as many booleans as the dimension holds, true where it selects. *)
        Lget m; Cast (false, T rt.list); Lset l;
        Lget l; call rt "cells"; Lget n; i32_ne;
        If (Bnone, fail ~kind:k_index rt (Messages.mask_size 1000001 1000002 |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
                     [ [ Lget l; call rt "cells"; i64_extend_u; call rt "itoa" ]; [ Lget n; i64_extend_u; call rt "itoa" ] ] [ Lget site ], []);
        Lget n; array_new_default rt.i32s; Lset out ]
      @ upto k n [ Lget l; Lget k; call rt "elem"; Lset x;
                   Lget x; g_true rt; ref_eq;
                   If (Bnone, [ Lget out; Lget used; Lget k; array_set rt.i32s; Lget used; I32 1; i32_add; Lset used ],
                       [ Lget x; g_false rt; ref_eq; Lget x; ref_is_null; i32_or;
                         If (Bnone, [], fail rt (Messages.index_type a1) [ [ Lget x; call rt "describe" ] ] [ Lget site ]) ]) ]
      @ [ Lget used; array_new_default rt.i32s; Lset w; Lget w; I32 0; Lget out; I32 0; Lget used; array_copy rt.i32s rt.i32s; Lget w ]);
  (* The cells of a list at these places, a new list of [rows] by [cols]. *)
  def "pick_at" (fun rt -> [ nn rt.list; nn rt.i32s; I32; I32 ], [ v ], fun fb ->
      let i = local fb I32 and n = local fb I32 and w = local fb (nn rt.vals) in
      [ Lget 1; array_len; Lset n; Lget n; array_new_default rt.vals; Lset w ]
      @ upto i n [ Lget w; Lget i; Lget 0; Lget 1; Lget i; array_get rt.i32s; call rt "elem"; call rt "share"; array_set rt.vals ]
      @ [ Lget 2; Lget 3; Lget w; call rt "list_of" ]);
  (* xs[ix], one index that isn't a whole number: a column stays a column. A map takes a key. *)
  def "read1" (fun rt -> [ v; I32; I64; I64; v; I32 ], [ v ], fun fb ->
      let l = local fb (nn rt.list) and ks = local fb (nn rt.i32s) and k = local fb I32 in
      [ Lget 1; I32 3; i32_eq; Lget 4; Test (false, T rt.list); i32_eqz; i32_and;
        If (Bnone, [ Lget 0; Lget 4; Lget 5; call rt "index_v"; ret ], []);
        Lget 0; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.index_value a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 5 ]);
        Lget 0; Cast (false, T rt.list); Lset l;
        Lget 1; Lget 2; Lget 3; Lget 4; Lget l; call rt "cells"; Lget 5; call rt "positions"; Lset ks; Lget ks; array_len; Lset k;
        Lget l; Lget ks;
        Lget l; struct_get rt.list l_cols; I32 1; i32_eq; Lget l; struct_get rt.list l_rows; I32 1; i32_ne; i32_and;
        If (Bval I32, [ Lget k ], [ Lget k; If (Bval I32, [ I32 1 ], [ I32 1 ]) ]);
        Lget l; struct_get rt.list l_cols; I32 1; i32_eq; Lget l; struct_get rt.list l_rows; I32 1; i32_ne; i32_and;
        If (Bval I32, [ I32 1 ], [ Lget k ]);
        call rt "pick_at" ]);
  (* m[i, j]: a cell for two whole numbers, else the rows and columns they select. *)
  def "read2" (fun rt -> [ v; I32; I64; I64; v; I32; I64; I64; v; I32 ], [ v ], fun fb ->
      let l = local fb (nn rt.list) and rs = local fb (nn rt.i32s) and cs = local fb (nn rt.i32s) and ks = local fb (nn rt.i32s) in
      let i = local fb I32 and j = local fb I32 and r = local fb I32 and c = local fb I32 in
      [ Lget 0; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.index_value a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 9 ]);
        Lget 0; Cast (false, T rt.list); Lset l;
        Lget 1; i32_eqz; Lget 5; i32_eqz; i32_and;
        If (Bnone, [ Lget 2; i64 1; i64_lt_s; Lget 2; Lget l; struct_get rt.list l_rows; i64_extend_u; i64_gt_s; i32_or;
                     Lget 6; i64 1; i64_lt_s; i32_or; Lget 6; Lget l; struct_get rt.list l_cols; i64_extend_u; i64_gt_s; i32_or;
                     If (Bnone, outside2 rt [ Lget 2 ] [ Lget 6 ] [ Lget l; struct_get rt.list l_rows; i64_extend_u ] [ Lget l; struct_get rt.list l_cols; i64_extend_u ] 9, []);
                     Lget l; Lget 6; i32_wrap; I32 1; i32_sub; Lget l; struct_get rt.list l_rows; i32_mul; Lget 2; i32_wrap; I32 1; i32_sub; i32_add; call rt "elem"; ret ], []);
        Lget 1; Lget 2; Lget 3; Lget 4; Lget l; struct_get rt.list l_rows; Lget 9; call rt "positions"; Lset rs;
        Lget 5; Lget 6; Lget 7; Lget 8; Lget l; struct_get rt.list l_cols; Lget 9; call rt "positions"; Lset cs;
        Lget rs; array_len; Lset r; Lget cs; array_len; Lset c; Lget r; Lget c; i32_mul; array_new_default rt.i32s; Lset ks ]
      @ upto j c (upto i r [ Lget ks; Lget j; Lget r; i32_mul; Lget i; i32_add;
                             Lget cs; Lget j; array_get rt.i32s; Lget l; struct_get rt.list l_rows; i32_mul; Lget rs; Lget i; array_get rt.i32s; i32_add;
                             array_set rt.i32s ])
      @ [ Lget l; Lget ks; Lget r; Lget c; call rt "pick_at" ]);
  (* m[i, j] = x, both whole numbers: the list to keep, the same one when owned, else a copy. *)
  def "write2" (fun rt -> [ v; I64; I64; v; I32 ], [ v ], fun fb ->
      let l = local fb (nl rt.list) in
      [ Lget 0; Test (false, T rt.list); If (Bnone, [], fail rt (Messages.index_value a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 4 ]);
        Lget 0; Cast (false, T rt.list); Lset l;
        Lget l; struct_get rt.list l_owned; i32_eqz; If (Bnone, [ Lget l; as_non_null; call rt "copy_list"; Lset l ], []);
        Lget 1; i64 1; i64_lt_s; Lget 1; Lget l; struct_get rt.list l_rows; i64_extend_u; i64_gt_s; i32_or;
        Lget 2; i64 1; i64_lt_s; i32_or; Lget 2; Lget l; struct_get rt.list l_cols; i64_extend_u; i64_gt_s; i32_or;
        If (Bnone, fail ~kind:k_index rt (Messages.index_outside 1000001 1000002 |> fun m -> { m with text = replace m.text [ "1000001", a1; "1000002", a2 ] })
                     [ [ Lget 1; call rt "itoa" ]; [ Lget l; as_non_null; call rt "cells"; i64_extend_u; call rt "itoa" ] ] [ Lget 4 ], []);
        Lget l; as_non_null; Lget 2; i32_wrap; I32 1; i32_sub; Lget l; struct_get rt.list l_rows; i32_mul; Lget 1; i32_wrap; I32 1; i32_sub; i32_add;
        Lget 3; call rt "store_elt"; Lget l ]);
  (* x in xs: an element equal to x, or a key of a dictionary. *)
  def "member" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let l = local fb (nn rt.list) and n = local fb I32 and i = local fb I32 in
      [ Lget 1; Test (false, T rt.list);
        If (Bnone, [ Lget 1; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n ]
                   @ upto i n [ Lget 0; Lget l; Lget i; call rt "elem"; call rt "equal"; If (Bnone, [ g_true rt; ret ], []) ]
                   @ [ g_false rt; ret ], []);
        Lget 1; call rt "as_map"; Test (false, T rt.map);
        If (Bnone, [ Lget 0; Lget 2; call rt "check_key"; Lget 1; call rt "as_map"; Cast (false, T rt.map); Lget 0; call rt "map_find"; I32 0; i32_ge_s ] @ bool_of rt @ [ ret ], []) ]
      @ fail rt (Messages.cant_in a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
  (* Fill and Zeros of rows by columns. *)
  def "fill2" (fun rt -> [ v; v; v; I32 ], [ v ], fun fb ->
      let r = local fb I32 and c = local fb I32 and w = local fb (nn rt.vals) and i = local fb I32 in
      [ Lget 1; Lget 3; text rt "Fill"; call rt "count_arg"; Lset r; Lget 2; Lget 3; text rt "Fill"; call rt "count_arg"; Lset c;
        Lget r; i64_extend_u; Lget c; i64_extend_u; i64_mul; i64 (1 lsl 28); i64_gt_s; If (Bnone, fail rt Messages.range_too_long [] [ Lget 3 ], []);
        Lget r; Lget c; i32_mul; array_new_default rt.vals; Lset w; I32 0; Lset i;
        Block (Bnone, [ Loop (Bnone, [ Lget i; Lget w; array_len; i32_ge_u; Br_if 1; Lget w; Lget i; Lget 0; call rt "share"; array_set rt.vals;
                                       Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
        Lget r; Lget c; Lget w; call rt "list_of" ])

(* list.Max and list.Min, as Native.best: of a list, its largest or smallest; of two, the larger or smaller of each pair,
   a list taken cell by cell; missing gives missing. [op] is cmp's: 2 for >, 0 for <. *)
let () =
  def "pick_best" (fun rt -> [ v; v; I32; I32 ], [ v ], fun _ ->
      [ Lget 0; ref_is_null; Lget 1; ref_is_null; i32_or; If (Bnone, [ missing; ret ], []);
        Lget 2; Lget 1; Lget 0; Lget 3; call rt "cmp"; g_true rt; ref_eq; If (Bval v, [ Lget 1 ], [ Lget 0 ]) ]);
  def "best" (fun rt -> [ v; v; I32; nn rt.bytes; I32 ], [ v ], fun fb ->
      let l = local fb (nn rt.list) and n = local fb I32 and i = local fb I32 and acc = local fb v and w = local fb (nn rt.vals) in
      let la = local fb (nl rt.list) and lb = local fb (nl rt.list) and shape = local fb (nl rt.list) in
      let cell l x = [ Lget l; ref_is_null; If (Bval v, [ Lget x ], [ Lget l; as_non_null; Lget i; call rt "elem" ]) ] in
      [ Lget 1; g_undef rt; ref_eq;
        If (Bnone, [ Lget 0; Test (false, T rt.list); If (Bnone, [], [ Lget 0; ret ]);
                     Lget 0; Cast (false, T rt.list); Lset l; Lget l; call rt "cells"; Lset n;
                     Lget n; i32_eqz; If (Bnone, fail rt (Messages.empty_array "\003" |> fun m -> { m with text = replace m.text [ "\003", a1 ] }) [ [ Lget 3 ] ] [ Lget 4 ], []);
                     Lget l; I32 0; call rt "elem"; Lset acc; I32 1; Lset i;
                     Block (Bnone, [ Loop (Bnone, [ Lget i; Lget n; i32_ge_u; Br_if 1;
                                                    Lget acc; Lget l; Lget i; call rt "elem"; Lget 2; Lget 4; call rt "pick_best"; Lset acc;
                                                    Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
                     Lget acc; call rt "share"; ret ], []);
        Lget 0; Test (false, T rt.list); Lget 1; Test (false, T rt.list); i32_or; i32_eqz; If (Bnone, [ Lget 0; Lget 1; Lget 2; Lget 4; call rt "pick_best"; ret ], []);
        Lget 0; Test (false, T rt.list); If (Bnone, [ Lget 0; Cast (false, T rt.list); Lset la ], []);
        Lget 1; Test (false, T rt.list); If (Bnone, [ Lget 1; Cast (false, T rt.list); Lset lb ], []);
        Lget la; ref_is_null; If (Bval (nl rt.list), [ Lget lb ], [ Lget la ]); Lset shape;
        Lget la; ref_is_null; Lget lb; ref_is_null; i32_or; i32_eqz;
        If (Bnone, [ Lget la; struct_get rt.list l_rows; Lget lb; struct_get rt.list l_rows; i32_ne;
                     Lget la; struct_get rt.list l_cols; Lget lb; struct_get rt.list l_cols; i32_ne; i32_or;
                     If (Bnone, fail rt shape_msg [ [ Lget la; as_non_null; call rt "sizes" ]; [ Lget lb; as_non_null; call rt "sizes" ] ] [ Lget 4 ], []) ], []);
        Lget shape; struct_get rt.list l_rows; Lget shape; struct_get rt.list l_cols; i32_mul; Lset n; Lget n; array_new_default rt.vals; Lset w ]
      @ upto i n ([ Lget w; Lget i ] @ cell la 0 @ cell lb 1 @ [ Lget 2; Lget 4; call rt "pick_best"; call rt "share"; array_set rt.vals ])
      @ [ Lget shape; struct_get rt.list l_rows; Lget shape; struct_get rt.list l_cols; Lget w; call rt "list_of" ])

(* text.Number: an integer when the text is one that fits, else a float as JavaScript reads it, after the same grammar
   as the interpreter's; missing for a text that isn't a number. text.Decimals: n digits after the point. *)
let () =
  def "text_number" (fun rt -> [ v; I32 ], [ v ], fun fb ->
      let s = local fb (nn rt.bytes) and i = local fb I32 and x = local fb F64 and n = local fb I32 and acc = local fb I64 and c = local fb I32 in
      let neg = local fb I32 and whole = local fb I32 in
      need_text rt "Number" 0 1
      @ bytes_of rt 0 @ [ Lset s; Lget s; array_len; Lset n; Lget n; I32 65536; i32_gt_u; If (Bnone, [ missing; ret ], []) ]
      @ upto i n [ Lget i; Lget s; Lget i; array_get_u rt.bytes; store8 window ]
      @ [ Lget n; host rt "number"; Lset x; Lget x; Lget x; f64_ne; If (Bnone, [ missing; ret ], []);
          (* Whole: digits, after a sign, that fit in 63 bits. *)
          I32 1; Lset whole; I32 0; Lset i;
          Lget n; If (Bnone, [ Lget s; I32 0; array_get_u rt.bytes; Lset c; Lget c; I32 45; i32_eq; Lset neg;
                               Lget c; I32 45; i32_eq; Lget c; I32 43; i32_eq; i32_or; If (Bnone, [ I32 1; Lset i ], []) ], []);
          Block (Bnone, [ Loop (Bnone, [
              Lget i; Lget n; i32_ge_u; Br_if 1;
              Lget s; Lget i; array_get_u rt.bytes; I32 48; i32_sub; Lset c;
              Lget c; I32 9; i32_gt_u; If (Bnone, [ I32 0; Lset whole; Br 2 ], []);
              Lget acc; I64 922337203685477580L; i64_gt_u; If (Bnone, [ I32 0; Lset whole; Br 2 ], []);
              Lget acc; i64 10; i64_mul; Lget c; i64_extend_u; i64_add; Lset acc;
              Lget i; I32 1; i32_add; Lset i; Br 0 ]) ]);
          Lget whole;
          If (Bnone, [ Lget neg; If (Bval I64, [ i64 0; Lget acc; i64_sub ], [ Lget acc ]); Lset acc ]
                     @ [ Lget acc; i64 1; i64_shl; i64 1; i64_shr_s; Lget acc; i64_eq; Lget neg; Lget acc; i64 0; i64_le_s; i32_and; Lget neg; i32_eqz; Lget acc; i64 0; i64_ge_s; i32_and; i32_or; i32_and;
                         If (Bnone, [ Lget acc; call rt "box_i"; ret ], []) ], []);
          Lget x; call rt "box_f" ]);
  def "decimals" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let n = local fb I32 and b = local fb (nn rt.buf) and k = local fb I32 in
      [ Lget 0; call rt "is_int"; If (Bval I32, [ Lget 0; call rt "int_of"; i64 0; i64_ge_s; Lget 0; call rt "int_of"; i64 20; i64_le_s; i32_and ], [ I32 0 ]);
        If (Bnone, [], fail rt (Messages.decimals_count a1) [ [ Lget 0; call rt "describe" ] ] [ Lget 2 ]);
        Lget 0; call rt "int_of"; i32_wrap; Lset n;
        Lget 1; call rt "is_int";
        If (Bnone, [ call rt "buf_new"; Lset b; Lget b; Lget 1; call rt "int_of"; call rt "write_int";
                     Lget n; If (Bnone, [ Lget b; I32 46; call rt "buf_byte" ] @ upto k n [ Lget b; I32 48; call rt "buf_byte" ], []);
                     Lget b; call rt "buf_done"; ret ], []);
        Lget 1; Test (false, T rt.boxf);
        If (Bnone, [ call rt "buf_new"; Lset b; Lget b; I32 scratch; Lget 1; call rt "float_of"; Lget n; host rt "decimals"; call rt "buf_mem"; Lget b; call rt "buf_done"; ret ], []) ]
      @ fail rt (Messages.need_number "text.Decimals" a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
  (* random.Float: splitmix64 from the seed the loader drew, as the interpreter's from its own: 53 bits. *)
  def "random_float" (fun rt -> [ I32 ], [ v ], fun _ ->
      [ call rt "next_seed"; i64 11; i64_shr_u; Op 0xba (* f64.convert_i64_u *); F64 0x1p-53; f64_mul; call rt "box_f" ])

(* Messages.number_bytes of a count of bytes, a kind and its size, all known at the run: the kind and its size one
   operand, with the words between them. *)
let number_bytes rt n kind size site =
  let t = (Messages.number_bytes "\005" 1000001 1000003).text in
  let at x = let k = ref 0 in while String.sub t !k (String.length x) <> x do incr k done; !k in
  let a = at "1000003" and b = at "\005" and c = at "1000001" in
  let m = Messages.plain (String.sub t 0 a ^ a1 ^ String.sub t (a + 7) (b - a - 7) ^ a2 ^ String.sub t (c + 7) (String.length t - c - 7)) in
  fail rt m [ n; kind @ [ text rt (String.sub t (b + 1) (c - b - 1)) ] @ size @ [ call rt "cat3" ] ] [ Lget site ]

(* value.Text(x, most): at most [most] characters, the last an ellipsis when it is cut. text.Numbers: the numbers that
   the bytes of a text hold, little-endian. *)
let () =
  def "text_upto" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let t = local fb (nn rt.bytes) and most = local fb I32 and b = local fb (nn rt.buf) in
      [ Lget 1; call rt "is_int"; If (Bval I32, [ Lget 1; call rt "int_of"; i64 1; i64_ge_s ], [ I32 0 ]);
        If (Bnone, [], fail rt (Messages.text_most a1) [ [ Lget 1; call rt "describe" ] ] [ Lget 2 ]);
        Lget 1; call rt "int_of"; i64 (1 lsl 30); i64_gt_s; If (Bval I32, [ I32 (1 lsl 30) ], [ Lget 1; call rt "int_of"; i32_wrap ]); Lset most;
        Lget 0; call rt "text_of"; Lset t;
        Lget t; call rt "code_points"; Lget most; i32_le_u; If (Bnone, [ Lget t; ret ], []);
        call rt "buf_new"; Lset b; Lget b; Lget t; I32 0; Lget t; Lget most; I32 1; i32_sub; call rt "char_byte"; call rt "sub"; call rt "buf_add";
        Lget b; text rt "\xe2\x80\xa6"; call rt "buf_add"; Lget b; call rt "buf_done" ]);
  def "numbers" (fun rt -> [ v; v; I32 ], [ v ], fun fb ->
      let kind = local fb I32 and size = local fb I32 and s = local fb (nn rt.bytes) and n = local fb I32 and w = local fb (nn rt.vals) in
      let i = local fb I32 and k = local fb I32 and x = local fb I64 in
      let kinds = [ "u8", 1; "i8", 1; "u16", 2; "i16", 2; "u32", 4; "i32", 4; "f32", 4; "f64", 8 ] in
      need_text rt "Numbers" 0 2 @ need_text rt "Numbers" 1 2
      @ List.concat (List.mapi (fun j (name, sz) -> [ Lget 0; Cast (false, T rt.bytes); text rt name; call rt "bytes_eq"; If (Bnone, [ I32 (j + 1); Lset kind; I32 sz; Lset size ], []) ]) kinds)
      @ [ Lget kind; i32_eqz; If (Bnone, fail rt (Messages.number_kind "Numbers" a1) [ bytes_of rt 0 ] [ Lget 2 ], []) ]
      @ bytes_of rt 1 @ [ Lset s; Lget s; array_len; Lget size; Op 0x6e (* div_u *); Lset n;
          Lget n; Lget size; i32_mul; Lget s; array_len; i32_ne;
          If (Bnone, number_bytes rt [ Lget s; array_len; i64_extend_u; call rt "itoa" ] (bytes_of rt 0) [ Lget size; i64_extend_u; call rt "itoa" ] 2, []);
          Lget n; array_new_default rt.vals; Lset w ]
      @ upto i n [ i64 0; Lset x; Lget size; Lset k;
                   Block (Bnone, [ Loop (Bnone, [ Lget k; i32_eqz; Br_if 1; Lget k; I32 1; i32_sub; Lset k;
                                                  Lget x; i64 8; i64_shl; Lget s; Lget i; Lget size; i32_mul; Lget k; i32_add; array_get_u rt.bytes; i64_extend_u; i64_or; Lset x; Br 0 ]) ]);
                   Lget w; Lget i;
                   Lget kind; I32 7; i32_eq; If (Bval v, [ Lget x; i32_wrap; Op 0xbe (* f32.reinterpret_i32 *); Op 0xbb (* f64.promote_f32 *); call rt "box_f" ],
                     [ Lget kind; I32 8; i32_eq; If (Bval v, [ Lget x; Op 0xbf (* f64.reinterpret_i64 *); call rt "box_f" ],
                       [ Lget kind; I32 2; i32_eq; If (Bnone, [ Lget x; i64 56; i64_shl; i64 56; i64_shr_s; Lset x ], []);
                         Lget kind; I32 4; i32_eq; If (Bnone, [ Lget x; i64 48; i64_shl; i64 48; i64_shr_s; Lset x ], []);
                         Lget kind; I32 6; i32_eq; If (Bnone, [ Lget x; i64 32; i64_shl; i64 32; i64_shr_s; Lset x ], []);
                         Lget x; call rt "box_i" ]) ]);
                   array_set rt.vals ]
      @ [ I32 1; Lget n; Lget w; call rt "list_of" ])
