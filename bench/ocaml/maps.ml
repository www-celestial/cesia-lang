let maps n =
  let m = Hashtbl.create 16 in
  for k = 1 to n do
    Hashtbl.replace m ("key" ^ string_of_int k) k
  done;
  let total = ref 0 in
  for k = 1 to n do
    total := !total + Hashtbl.find m ("key" ^ string_of_int k)
  done;
  !total

let () = Printf.printf "%d\n" (maps 500000)
