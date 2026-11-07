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

(* The units of the plugins loaded so far, and the file of each: a later plugin is checked against them, as against the
   program's own. *)
let loaded : (string, global * string) Hashtbl.t = Hashtbl.create 16

let reserved name = String.starts_with ~prefix:"Cesia" name
let frozen name = name = "Cesia_v1" || String.starts_with ~prefix:"Cesia_v1_" name

(* The plugin's units against the program's: each interface it was compiled with, and each implementation it calls, the
   program's own, else the plugin is from another build. [strict], for the engine of a native package: none of its units
   is named as Cesia's, it sees no interface of Cesia's but the frozen ones, and every implementation it calls is there. *)
let consistent ~strict units =
  let program = Hashtbl.create 1024 in
  List.iter (fun g -> Hashtbl.replace program g.gname g) (ndl_getmap ());
  Hashtbl.iter (fun name (g, _) -> Hashtbl.replace program name g) loaded;
  let ours = Hashtbl.create 16 in
  List.iter (fun u -> Hashtbl.replace ours u.name u.crc) units;
  let intf (name, crc) =
    match crc, Hashtbl.find_opt program name with
    | _ when strict && reserved name && not (frozen name || Hashtbl.mem ours name) -> Error ("it uses " ^ name ^ ", inside Cesia")
    | Some c, Some { crc_intf = Some c'; _ } when c <> c' -> Error ("interface of " ^ name ^ " differs")
    | _ -> Ok ()
  in
  let impl (name, crc) =
    match crc, Hashtbl.find_opt ours name, Hashtbl.find_opt program name with
    | None, None, None when strict -> Error ("its engine needs " ^ name ^ ", which this Cesia doesn't hold")
    | None, _, _ -> Ok ()
    | Some c, Some c', _ -> if c = c' then Ok () else Error ("implementation of " ^ name ^ " differs")
    | Some c, None, Some { crc_impl = Some c'; _ } -> if c = c' then Ok () else Error ("implementation of " ^ name ^ " differs")
    | Some _, None, _ -> Error ("its engine needs " ^ name ^ ", which this Cesia doesn't hold")
  in
  let rec all f = function [] -> Ok () | x :: rest -> (match f x with Ok () -> all f rest | e -> e) in
  all
    (fun u ->
       match Hashtbl.find_opt loaded u.name with
       | Some (_, path) -> Error (u.name ^ " came already with " ^ path)
       | None when Hashtbl.mem program u.name -> Error (u.name ^ " is in the program already")
       | None when strict && reserved u.name -> Error (u.name ^ " is a name of Cesia")
       | None -> (match all intf u.imports_cmi with Ok () -> all impl u.imports_cmx | e -> e))
    units

let load ?(global = false) ?(strict = false) path =
  match ndl_open path global with
  | exception e -> Error (Printexc.to_string e)
  | handle, header ->
    if header.magic <> magic then Error "made by another OCaml"
    else begin
      match consistent ~strict header.units with
      | Error _ as e -> e
      | Ok () ->
        ndl_register handle (Array.of_list ("_shared_startup" :: List.concat_map (fun u -> u.defines) header.units));
        List.iter
          (fun u ->
             let g = { gname = u.name; crc_intf = Option.join (List.assoc_opt u.name u.imports_cmi); crc_impl = Some u.crc; syms = [] } in
             Hashtbl.replace loaded u.name (g, path))
          header.units;
        (match
           ndl_run handle "_shared_startup";
           List.iter (fun u -> List.iter (ndl_run handle) u.defines) header.units
         with
         | () -> Ok ()
         | exception e -> Error ("its initialisation raised " ^ Printexc.to_string e))
    end
