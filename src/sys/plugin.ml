(* What OCaml's Dynlink does for one native plugin, through the same primitives of the runtime: the library itself, linked
   in, would cost every start-up its initialisation, about 100,000 instructions. The types are those of OCaml 5.5
   (Cmxs_format and the globals map of the link), checked by the plugin's magic number before anything else is read. *)

type handle

type unit_ = {
  name : string;
  crc : string;
  imports_cmi : (string * string option) list;
  imports_cmx : (string * string option) list;
  defines : string list;
}

type header = { magic : string; units : unit_ list }
type global = { gname : string; crc_intf : string option; crc_impl : string option; syms : string list }

external ndl_open : string -> bool -> handle * header = "caml_natdynlink_open"
external ndl_register : handle -> string array -> unit = "caml_natdynlink_register"
external ndl_run : handle -> string -> unit = "caml_natdynlink_run"
external ndl_getmap : unit -> global list = "caml_natdynlink_getmap"

(* Config.cmxs_magic_number of OCaml 5.5: another OCaml writes other headers, which this reading would get wrong. *)
let magic = "Caml1999D037"

(* The plugin's units against the program's: each interface it was compiled with, and each implementation it calls, the
   program's own, else the plugin is from another build. *)
let consistent units =
  let program = Hashtbl.create 1024 in
  List.iter (fun g -> Hashtbl.replace program g.gname g) (ndl_getmap ());
  let ours = Hashtbl.create 16 in
  List.iter (fun u -> Hashtbl.replace ours u.name u.crc) units;
  let intf (name, crc) =
    match crc, Hashtbl.find_opt program name with
    | Some c, Some { crc_intf = Some c'; _ } when c <> c' -> Error ("interface of " ^ name ^ " differs")
    | _ -> Ok ()
  in
  let impl (name, crc) =
    match crc, Hashtbl.find_opt ours name, Hashtbl.find_opt program name with
    | None, _, _ -> Ok ()
    | Some c, Some c', _ -> if c = c' then Ok () else Error ("implementation of " ^ name ^ " differs")
    | Some c, None, Some { crc_impl = Some c'; _ } -> if c = c' then Ok () else Error ("implementation of " ^ name ^ " differs")
    | Some _, None, _ -> Error ("no implementation of " ^ name)
  in
  let rec all f = function [] -> Ok () | x :: rest -> (match f x with Ok () -> all f rest | e -> e) in
  all
    (fun u ->
       if Hashtbl.mem program u.name then Error (u.name ^ " is in the program already")
       else match all intf u.imports_cmi with Ok () -> all impl u.imports_cmx | e -> e)
    units

let load path =
  match ndl_open path false with
  | exception e -> Error (Printexc.to_string e)
  | handle, header ->
    if header.magic <> magic then Error "made by another OCaml"
    else begin
      match consistent header.units with
      | Error _ as e -> e
      | Ok () ->
        ndl_register handle (Array.of_list ("_shared_startup" :: List.concat_map (fun u -> u.defines) header.units));
        (match
           ndl_run handle "_shared_startup";
           List.iter (fun u -> List.iter (ndl_run handle) u.defines) header.units
         with
         | () -> Ok ()
         | exception e -> Error ("its initialisation raised " ^ Printexc.to_string e))
    end
