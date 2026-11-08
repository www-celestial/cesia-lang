let mandel w h maxit =
  let total = ref 0 in
  for py = 0 to h - 1 do
    let y0 = (2.0 *. float py /. float h) -. 1.0 in
    for px = 0 to w - 1 do
      let x0 = (3.0 *. float px /. float w) -. 2.0 in
      let x = ref 0.0 and y = ref 0.0 and x2 = ref 0.0 and y2 = ref 0.0 and it = ref 0 in
      while !x2 +. !y2 < 4.0 && !it < maxit do
        y := (2.0 *. !x *. !y) +. y0;
        x := !x2 -. !y2 +. x0;
        x2 := !x *. !x;
        y2 := !y *. !y;
        incr it
      done;
      total := !total + !it
    done
  done;
  !total

let () = Printf.printf "%d\n" (mandel 600 400 200)
