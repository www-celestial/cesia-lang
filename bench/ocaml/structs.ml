(* A particle is an immutable record: each step makes a new one, as the other versions do. *)
type particle = { x : float; y : float; vx : float; vy : float }

let simulate n steps =
  let ps = Array.init n (fun i -> { x = float (i + 1); y = 0.0; vx = 1.0; vy = float (i + 1) *. 0.5 }) in
  let dt = 0.001 in
  for _ = 1 to steps do
    for i = 0 to n - 1 do
      let p = ps.(i) in
      let vy = p.vy -. (9.81 *. dt) in
      ps.(i) <- { x = p.x +. (p.vx *. dt); y = p.y +. (vy *. dt); vx = p.vx; vy }
    done
  done;
  Array.fold_left (fun e p -> e +. p.x +. p.y) 0.0 ps

let () = Printf.printf "%.6f\n" (simulate 1000 5000)
