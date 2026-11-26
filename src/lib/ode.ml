(* The dense output of std/ode. std/ode.ce solves, and keeps each step it takes in chunks, arrays of floats of a fixed
   size: t, h, then n floats each of y, k1, k3, k4, k5 and k6 for Dormand and Prince, or of y, q1, q2 and q3 for the
   Rosenbrock method Rodas5P. The next step, or the tail of the Solution, holds the state y1 at the end of a step and,
   for Dormand and Prince, k7, the derivative there. Here, the state at a time inside a step: for Dormand and Prince, the
   dense output of order 4 of Shampine (1986), in the form Hairer, Nørsett and Wanner give it for DOPRI5 (I, §II.6),

     y(t + θh) = y + θ (r2 + (1 - θ) (r3 + θ (r4 + (1 - θ) r5))),

   r2 = y1 - y, r3 = h k1 - r2, r4 = r2 - h k7 - r3 and r5 = h (d1 k1 + d3 k3 + d4 k4 + d5 k5 + d6 k6 + d7 k7); for
   Rodas5P, (1 - θ) y + θ (y1 + (1 - θ) (q1 + θ (q2 + θ q3))). Each float is computed by the operations, in the order,
   of the same formulas on whole arrays, as std/ode.ce computed them before: the states are the same to the last bit.
   Every input is checked first, so that no index leaves its array, whatever a Solution built by hand holds. *)
open Types

let d1 = -12715105075.0 /. 11282082432.0
let d3 = 87487479700.0 /. 32700410799.0
let d4 = -10690763975.0 /. 1880347072.0
let d5 = 701980252875.0 /. 199316789632.0
let d6 = -1453857185.0 /. 822651844.0
let d7 = 69997945.0 /. 29380423.0
let get = Float.Array.get
let set = Float.Array.set

(* The floats of a step. *)
let width stiff n = ((if stiff then 4 else 6) * n) + 2

(* Into r, 5 n floats, what the dense output of the step at b.(o) needs at every time inside it, from its end at e.(eo):
   y, r2, r3, r4 and r5 for Dormand and Prince; y, y1, q1, q2 and q3 for Rodas5P. *)
let[@inline] prepare stiff n b o e eo r =
  if stiff then begin
    for i = 0 to n - 1 do
      set r i (get b (o + 2 + i));
      set r (n + i) (get e (eo + i))
    done;
    for c = 2 * n to (5 * n) - 1 do
      set r c (get b (o + 2 - n + c))
    done
  end
  else begin
    let h = get b (o + 1) in
    let hd1 = h *. d1 and hd3 = h *. d3 and hd4 = h *. d4 and hd5 = h *. d5 and hd6 = h *. d6 and hd7 = h *. d7 in
    for i = 0 to n - 1 do
      let y = get b (o + 2 + i) and k1 = get b (o + 2 + n + i) and k7 = get e (eo + n + i) in
      let r2 = get e (eo + i) -. y in
      let hk1 = h *. k1 in let r3 = hk1 -. r2 in
      set r i y;
      set r (n + i) r2;
      set r ((2 * n) + i) r3;
      let hk7 = h *. k7 in set r ((3 * n) + i) (r2 -. hk7 -. r3);
      let p1 = hd1 *. k1 and p3 = hd3 *. get b (o + 2 + (2 * n) + i) and p4 = hd4 *. get b (o + 2 + (3 * n) + i) in
      let p5 = hd5 *. get b (o + 2 + (4 * n) + i) and p6 = hd6 *. get b (o + 2 + (5 * n) + i) and p7 = hd7 *. k7 in
      set r ((4 * n) + i) (p1 +. p3 +. p4 +. p5 +. p6 +. p7)
    done
  end

(* The state at the fraction th of the step that r is prepared for, into out.(at + i * stride) for i from 0 to n - 1. *)
let[@inline] fill stiff n r th out at stride =
  let w = 1. -. th in
  if stiff then
    for i = 0 to n - 1 do
      let p = th *. get r ((4 * n) + i) in let q = get r ((3 * n) + i) +. p in
      let p = th *. q in let q = get r ((2 * n) + i) +. p in
      let wq = w *. q in let s = th *. (get r (n + i) +. wq) and wr = w *. get r i in set out (at + (i * stride)) (wr +. s)
    done
  else
    for i = 0 to n - 1 do
      let p = w *. get r ((4 * n) + i) in let p = th *. (get r ((3 * n) + i) +. p) in
      let p = w *. (get r ((2 * n) + i) +. p) in let p = th *. (get r (n + i) +. p) in
      set out (at + (i * stride)) (get r i +. p)
    done

let fail ctx = Runtime.fail ctx Type Messages.ode_bad
let number ctx = function Float x -> x | Int i -> float_of_int i | _ -> fail ctx

(* The n floats of an array of n numbers. *)
let floats ctx n = function
  | Array a when a.rows * a.cols = n -> Float.Array.init n (fun k -> number ctx (Value.elt a k))
  | _ -> fail ctx

(* The time of a tail, [t, y1, k7] or [t, y1] for Rodas5P, and the end of its step as [prepare] takes it: y1, then
   k7. *)
let ends ctx stiff n = function
  | Array a when a.rows * a.cols >= if stiff then 2 else 3 ->
    let y1 = floats ctx n (Value.elt a 1) in
    number ctx (Value.elt a 0), if stiff then y1 else Float.Array.append y1 (floats ctx n (Value.elt a 2))
  | _ -> fail ctx

let flag ctx = function True -> true | False -> false | _ -> fail ctx
let size ctx = function Int n when n >= 1 -> n | _ -> fail ctx

(* states(stiff, n, chunks, count, width, per, tail, till, ts): the m x n matrix of the states at the m times of ts, or
   the place, from 1, of the first one that is no finite number or lies outside the solution, from its first time to
   till: std/ode.ce says which. A time equal to the end of the last step, tail[1], takes y1 itself. The step of a time
   is the last whose start is not past it, sought from the step of the time before: forward by strides that double, then
   by halves inside the last stride, the search of Bentley and Yao (1976), about 2 log2 d looks for a step d steps
   ahead; back, by halves from the first step. A time inside the step of the time before needs no search. So times in
   order walk the steps once, and the dense output of a step is prepared once for the times in it. *)
let states ctx (a : t array) =
  let stiff = flag ctx a.(0) and n = size ctx a.(1) in
  (* First the tail, whose n floats bound n, so that width can't overflow; then divisions, never a product that
     could. *)
  let last, e = ends ctx stiff n a.(6) in
  let per = size ctx a.(5) in
  let width = match a.(4) with Int w when w = width stiff n -> w | _ -> fail ctx in
  let chunks =
    match a.(2) with
    | Array l ->
      Array.init (l.rows * l.cols) (fun k ->
          match Value.elt l k with
          | Array ({ store = F d; _ } as c) when c.rows * c.cols / width >= per -> d
          | _ -> fail ctx)
    | _ -> fail ctx
  in
  let count =
    match a.(3) with
    | Int c when c >= 0 && (c = 0 || (c - 1) / per < Array.length chunks) -> c
    | _ -> fail ctx
  in
  let till = number ctx a.(7) in
  let ts = match a.(8) with Array t -> t | _ -> fail ctx in
  let m = ts.rows * ts.cols in
  let cells = Runtime.cells ctx m n in
  (* Each time: its n cells, and at most one step prepared, 5 n. *)
  Runtime.pay ctx (6 * cells);
  let out = Runtime.alloc_float ctx cells 0. in
  let[@inline] start k =
    let c = k / per in
    get chunks.(c) ((k - (c * per)) * width)
  in
  let first = if count = 0 then last else start 0 in
  let dir = if till >= first then 1. else -1. in
  let[@inline] find k u =
    let lo = ref (max k 0) and hi = ref (count - 1) in
    if k >= 0 && dir *. (start k -. u) > 0. then begin
      lo := 0;
      hi := k - 1
    end
    else begin
      let stride = ref 1 and going = ref true in
      while !going && !lo < !hi do
        let c = min (!lo + !stride) !hi in
        if dir *. (start c -. u) <= 0. then begin
          lo := c;
          stride := 2 * !stride
        end
        else begin
          hi := c - 1;
          going := false
        end
      done
    end;
    while !lo < !hi do
      let mid = (!lo + !hi + 1) / 2 in
      if dir *. (start mid -. u) <= 0. then lo := mid else hi := mid - 1
    done;
    !lo
  in
  let r = Float.Array.make (5 * n) 0. in
  (* The step prepared in r, -1 for none: its start t0, its h, and t1, the start of the next one. *)
  let k = ref (-1) and t0 = ref 0. and h = ref 0. and t1 = ref 0. and wrong = ref 0 and j = ref 0 in
  while !wrong = 0 && !j < m do
    (* As 1.0 * x: an integer becomes its float; anything else that is no finite number, nan. *)
    let u =
      match ts.store with
      | F d -> get d !j
      | _ -> (match Value.elt ts !j with Float x -> x | Int i -> float_of_int i | _ -> nan)
    in
    if not ((u -. first) *. (u -. till) <= 0.) then wrong := !j + 1
    else begin
      if count = 0 || u = last then
        for i = 0 to n - 1 do
          set out (!j + (i * m)) (get e i)
        done
      else begin
        if not (!k >= 0 && dir *. (!t0 -. u) <= 0. && (!k = count - 1 || dir *. (!t1 -. u) > 0.)) then begin
          let q = find !k u in
          k := q;
          let c = q / per in
          let b = chunks.(c) and o = (q - (c * per)) * width in
          t0 := get b o;
          h := get b (o + 1);
          if q = count - 1 then prepare stiff n b o e 0 r
          else begin
            let c = (q + 1) / per in
            let o1 = (q + 1 - (c * per)) * width in
            t1 := get chunks.(c) o1;
            prepare stiff n b o chunks.(c) (o1 + 2) r
          end
        end;
        fill stiff n r ((u -. !t0) /. !h) out !j m
      end;
      incr j
    end
  done;
  if !wrong > 0 then Int !wrong else Arrays.shaped [| m; n |] (F out)

(* stateIn(stiff, n, b, o, tail, u): the state, 1 x n, at u inside the step at b[o + 1] that tail ends. *)
let state_in ctx (a : t array) =
  let stiff = flag ctx a.(0) and n = size ctx a.(1) in
  let _, e = ends ctx stiff n a.(4) in
  let b, o =
    match a.(2), a.(3) with
    | Array ({ store = F d; _ } as c), Int o when o >= 0 && o <= (c.rows * c.cols) - width stiff n -> d, o
    | _ -> fail ctx
  in
  let u = number ctx a.(5) in
  Runtime.pay ctx (5 * n);
  let r = Float.Array.make (5 * n) 0. and out = Runtime.alloc_float ctx n 0. in
  prepare stiff n b o e 0 r;
  fill stiff n r ((u -. get b o) /. get b (o + 1)) out 0 1;
  Arrays.shaped [| 1; n |] (F out)

let natives =
  [ "states", Native.nat "states" 9 9 states; "stateIn", Native.nat ~ret:(fun _ -> TFA) "stateIn" 6 6 state_in ]
