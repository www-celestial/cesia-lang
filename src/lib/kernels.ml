type op = Add | Sub | Mul | Div

let both op x y =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i +. Float.Array.get y i) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i -. Float.Array.get y i) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i *. Float.Array.get y i) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i /. Float.Array.get y i) done);
  out

let right op x s =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i +. s) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i -. s) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i *. s) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (Float.Array.get x i /. s) done);
  out

let left op s y =
  let n = Float.Array.length y in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi ->
      match op with
      | Add -> for i = lo to hi - 1 do Float.Array.set out i (s +. Float.Array.get y i) done
      | Sub -> for i = lo to hi - 1 do Float.Array.set out i (s -. Float.Array.get y i) done
      | Mul -> for i = lo to hi - 1 do Float.Array.set out i (s *. Float.Array.get y i) done
      | Div -> for i = lo to hi - 1 do Float.Array.set out i (s /. Float.Array.get y i) done);
  out

let map1 f x =
  let n = Float.Array.length x in
  let out = Float.Array.create n in
  Par.ranges n (fun lo hi -> for i = lo to hi - 1 do Float.Array.set out i (f (Float.Array.get x i)) done);
  out

(* In blocks of a fixed size, so that the rounding doesn't depend on the number of cores. *)
let block = 1 lsl 16

let sum x =
  let n = Float.Array.length x in
  let blocks = (n + block - 1) / block in
  let totals = Float.Array.make blocks 0. in
  Par.ranges ~grain:2 blocks (fun lo hi ->
      for b = lo to hi - 1 do
        let acc = ref 0. in
        for i = b * block to min n ((b + 1) * block) - 1 do acc := !acc +. Float.Array.get x i done;
        Float.Array.set totals b !acc
      done);
  Float.Array.fold_left ( +. ) 0. totals

let fast_matmul = ref (fun ~rows:_ ~cols:_ ~inner:_ ~out:_ _ _ -> false)

(* The grain of a loop over columns of this many cells each. *)
let column_grain cells = max 1 ((1 lsl 17) / max 1 cells)

(* By columns, to follow the storage order. *)
let matmul ~rows ~cols ~inner ~out x y =
  if rows > 0 && inner > 0 && not (!fast_matmul ~rows ~cols ~inner ~out x y) then
    Par.ranges ~grain:(column_grain (rows * inner)) cols (fun lo hi ->
        for j = lo to hi - 1 do
          let dst = j * rows in
          for k = 0 to inner - 1 do
            let b = Float.Array.get y ((j * inner) + k) in
            let src = k * rows in
            for i = 0 to rows - 1 do
              Float.Array.set out (dst + i) (Float.Array.get out (dst + i) +. (Float.Array.get x (src + i) *. b))
            done
          done
        done);
  out

let insertion a lo hi cmp =
  for i = lo + 1 to hi - 1 do
    let x = a.(i) in
    let j = ref (i - 1) in
    while !j >= lo && cmp a.(!j) x > 0 do
      a.(!j + 1) <- a.(!j);
      decr j
    done;
    a.(!j + 1) <- x
  done

(* Two sorted runs of [src], from lo to mid and from mid to hi, into [dst] from lo. *)
let merge src dst lo mid hi cmp =
  let i = ref lo and j = ref mid in
  for k = lo to hi - 1 do
    if !i < mid && (!j >= hi || cmp src.(!i) src.(!j) <= 0) then begin
      dst.(k) <- src.(!i);
      incr i
    end else begin
      dst.(k) <- src.(!j);
      incr j
    end
  done

let rec sort_range a b lo hi cmp =
  if hi - lo <= 16 then insertion a lo hi cmp
  else begin
    let mid = lo + ((hi - lo) / 2) in
    sort_range a b lo mid cmp;
    sort_range a b mid hi cmp;
    if cmp a.(mid - 1) a.(mid) > 0 then begin
      Array.blit a lo b lo (hi - lo);
      merge b a lo mid hi cmp
    end
  end

(* Sorts one run per core, then merges them two by two, from one array to the other. *)
let sort_parallel a b n cmp =
  let rec power k = if 2 * k > min (Par.cores ()) (n / (1 lsl 15)) then k else power (2 * k) in
  let runs = power 1 in
  let bound k = n * k / runs in
  Par.each runs (fun k -> sort_range a b (bound k) (bound (k + 1)) cmp);
  let rec merge_up src dst width =
    if width >= runs then src
    else begin
      Par.each (runs / (2 * width)) (fun k ->
          let lo = 2 * k * width in
          merge src dst (bound lo) (bound (lo + width)) (bound (lo + (2 * width))) cmp);
      merge_up dst src (2 * width)
    end
  in
  merge_up a b 1

let sort_positions ?(parallel = false) n cmp =
  let a = Array.init n Fun.id and b = Array.make n 0 in
  if parallel && n >= 1 lsl 17 && Par.cores () > 1 then sort_parallel a b n cmp
  else begin
    sort_range a b 0 n cmp;
    a
  end

let transpose ~rows ~cols x =
  let n = rows * cols in
  let out = Float.Array.create n in
  if n > 0 then
    Par.ranges ~grain:(column_grain rows) cols (fun lo hi ->
        for j = lo to hi - 1 do
          for i = 0 to rows - 1 do
            Float.Array.set out ((i * cols) + j) (Float.Array.get x ((j * rows) + i))
          done
        done);
  out
