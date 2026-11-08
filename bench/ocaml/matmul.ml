let matmul n =
  let a = Array.make (n * n) 0.0 and b = Array.make (n * n) 0.0 and c = Array.make (n * n) 0.0 in
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      a.((i * n) + j) <- float (i + j) *. 0.5;
      b.((i * n) + j) <- float (i - j) *. 0.25
    done
  done;
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      let s = ref 0.0 in
      for k = 0 to n - 1 do
        s := !s +. (a.((i * n) + k) *. b.((k * n) + j))
      done;
      c.((i * n) + j) <- !s
    done
  done;
  c.(n + 1)

let () = Printf.printf "%.6f\n" (matmul 300)
