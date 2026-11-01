type op = Add | Sub | Mul | Div

let both op x y =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  (match op with
   | Add -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i +. Float.Array.get y i) done
   | Sub -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i -. Float.Array.get y i) done
   | Mul -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i *. Float.Array.get y i) done
   | Div -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i /. Float.Array.get y i) done);
  out

let right op x s =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  (match op with
   | Add -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i +. s) done
   | Sub -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i -. s) done
   | Mul -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i *. s) done
   | Div -> for i = 0 to n - 1 do Float.Array.set out i (Float.Array.get x i /. s) done);
  out

let left op s y =
  let n = Float.Array.length y in
  let out = Float.Array.create n in
  (match op with
   | Add -> for i = 0 to n - 1 do Float.Array.set out i (s +. Float.Array.get y i) done
   | Sub -> for i = 0 to n - 1 do Float.Array.set out i (s -. Float.Array.get y i) done
   | Mul -> for i = 0 to n - 1 do Float.Array.set out i (s *. Float.Array.get y i) done
   | Div -> for i = 0 to n - 1 do Float.Array.set out i (s /. Float.Array.get y i) done);
  out

let map1 f x =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  for i = 0 to n - 1 do Float.Array.set out i (f (Float.Array.get x i)) done;
  out

let sum x =
  let acc = ref 0. in
  for i = 0 to Float.Array.length x - 1 do acc := !acc +. Float.Array.get x i done;
  !acc

(* By columns, to follow the storage order. *)
let matmul ~rows ~cols ~inner ~out x y =
  if rows > 0 && inner > 0 then
    for j = 0 to cols - 1 do
      let dst = j * rows in
      for k = 0 to inner - 1 do
        let b = Float.Array.get y ((j * inner) + k) in
        let src = k * rows in
        for i = 0 to rows - 1 do
          Float.Array.set out (dst + i) (Float.Array.get out (dst + i) +. (Float.Array.get x (src + i) *. b))
        done
      done
    done;
  out

let transpose ~rows ~cols x =
  let n = rows * cols in
  let out = Float.Array.create n in
  if n > 0 then
    for j = 0 to cols - 1 do
      for i = 0 to rows - 1 do
        Float.Array.set out ((i * cols) + j) (Float.Array.get x ((j * rows) + i))
      done
    done;
  out
