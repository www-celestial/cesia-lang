(* The same with OCaml's persistent map, a balanced tree: each write gives a new map, as Cesia's do. *)
module M = Map.Make (String)

let maps n =
  let m = ref M.empty in
  for k = 1 to n do
    m := M.add ("key" ^ string_of_int k) k !m
  done;
  let total = ref 0 in
  for k = 1 to n do
    total := !total + M.find ("key" ^ string_of_int k) !m
  done;
  !total

let () = Printf.printf "%d\n" (maps 500000)
