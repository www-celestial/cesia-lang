(* Calls through an array of functions. OCaml has no value of changing kind: the numbers are all floats here. *)
let dyn n =
  let ops = [| (fun a b -> a +. b); (fun a b -> (a *. 0.5) +. b) |] in
  let xs = [| 1.0; 2.5; 3.0; 4.5 |] in
  let total = ref 0.0 in
  for i = 1 to n do
    let f = ops.(i mod 2) in
    let x = xs.(i mod 4) in
    total := f !total x;
    if !total > 1000000.0 then total := !total /. 2.0
  done;
  !total

let () = Printf.printf "%.6f\n" (dyn 10000000)
