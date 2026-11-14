(* The text of a float as Cesia writes it, the bytes of C's printf "%.15g", else "%.16g", else "%.17g" (the first that
   reads back to the same float), then "1.0" for a whole number and "1e15", "1.5e-7" for an exponent; about 10 times
   faster than calling printf and strtod for each.

   How. A finite x > 0 is M * 2^e2, M = 4 * its mantissa. The decimals that read back to x lie between the midpoints with
   its neighbors, (M - 2) * 2^e2 and (M + 2) * 2^e2 (M - 1 below a power of 2, the step there being half), the
   midpoints included when the mantissa is even, as strtod rounds a half to even. Ryu (Adams, PLDI 2018) scales the three
   at once: vr, vp, vm = floor(M * 2^e2 / 10^e10) for M, M + 2 and M - 2, each by a product of M with an entry of 126
   bits of Pow5, then a shift. vr has 18 or 19 digits (17 when e2 is in -1..3, and then exact): rounded to P digits,
   a half to even, it gives the digits of %.Pg, which read back to x exactly when they lie between vm and vp. Ryu goes on
   to the shortest digits; Cesia keeps the first of 15, 16 and 17, as before. A subnormal is first normalized, its
   mantissa shifted left by s, its bounds then 2^(s+1) away: its vr has as many digits.

   Exact. Each product is the exact floor of its quotient, for every e2 a double has and every M it brings: this was
   checked with exact integers, the least and the most of a * M mod m over the range of M by Euclid's recursion, as
   Ryu's own analysis (EuclidMinMax) does; the smallest margin is 7e-20 of a step. The results stay below 2^62. *)

let mask = (1 lsl 30) - 1

(* Limb k of entry e of a table of Pow5. *)
let[@inline] limb tab e k = Int32.to_int (String.get_int32_le tab (((5 * e) + k) * 4))

(* floor(m * t / 2^j), t the entry t0..t4 (126 bits), m < 2^55, j in 118..125: columns of 30 bits, each below 2^61. *)
let[@inline] mul_shift t0 t1 t2 t3 t4 m j =
  let m0 = m land mask and m1 = m lsr 30 in
  let c0 = t0 * m0 in
  let c1 = (t1 * m0) + (t0 * m1) + (c0 lsr 30) in
  let c2 = (t2 * m0) + (t1 * m1) + (c1 lsr 30) in
  let c3 = (t3 * m0) + (t2 * m1) + (c2 lsr 30) in
  let c4 = (t4 * m0) + (t3 * m1) + (c3 lsr 30) in
  let c5 = (t4 * m1) + (c4 lsr 30) in
  if j >= 120 then ((c4 land mask) lsr (j - 120)) lor (c5 lsl (150 - j))
  else ((c3 land mask) lsr (j - 90)) lor ((c4 land mask) lsl (120 - j)) lor (c5 lsl (150 - j))

(* floor(e * log10 2), floor(e * log10 5), bits of 5^e: Ryu's, exact for e up to 1650, 2620 and 3528. *)
let[@inline] log10_pow2 e = (e * 78913) lsr 18
let[@inline] log10_pow5 e = (e * 732923) lsr 20
let[@inline] pow5_bits e = ((e * 1217359) lsr 19) + 1

let rec multiple_of_pow5 m q = q = 0 || (m mod 5 = 0 && multiple_of_pow5 (m / 5) (q - 1))

(* Is M * 2^e2 / 10^e10 an integer? q = e10 when e2 >= 0, else e10 - e2. *)
let exact up q m = q = 0 || if up then multiple_of_pow5 m q else q < 56 && m land ((1 lsl q) - 1) = 0

let[@inline] pow10 r = match r with 0 -> 1 | 1 -> 10 | 2 -> 100 | 3 -> 1000 | _ -> 10000

(* v / 10^r, r in 1..4, by constants, which the compiler makes multiplications. *)
let[@inline] div_pow10 v r = match r with 1 -> v / 10 | 2 -> v / 100 | 3 -> v / 1000 | _ -> v / 10000

(* Does d * 10^r lie between lo and hi? *)
let[@inline] fits lo hi r d =
  let c = d * pow10 r in
  lo <= c && c <= hi

(* vr rounded to its digits but the last r, a half to even; [exact] says vr is the quotient itself, not its floor. *)
let[@inline] round vr exact r =
  if r = 0 then vr
  else begin
    let p = pow10 r in
    let t = div_pow10 vr r in
    let rest = vr - (t * p) and half = p / 2 in
    if rest > half || (rest = half && ((not exact) || t land 1 = 1)) then t + 1 else t
  end

let pairs =
  "00010203040506070809101112131415161718192021222324252627282930313233343536373839\
   40414243444546474849505152535455565758596061626364656667686970717273747576777879\
   8081828384858687888990919293949596979899"

(* The n digits of d > 0 at b.[at] .. b.[at + n - 1]. *)
let digits b at n d =
  let d = ref d and j = ref (at + n - 1) in
  while !d >= 100 do
    let q = !d / 100 in
    let r = 2 * (!d - (q * 100)) in
    Bytes.set b !j pairs.[r + 1];
    Bytes.set b (!j - 1) pairs.[r];
    d := q;
    j := !j - 2
  done;
  if !d >= 10 then begin
    Bytes.set b !j pairs.[(2 * !d) + 1];
    Bytes.set b (!j - 1) pairs.[2 * !d]
  end
  else Bytes.set b !j (Char.chr (48 + !d))

let put b at s =
  Bytes.blit_string s 0 b at (String.length s);
  at + String.length s

let zeros b at n =
  Bytes.fill b at n '0';
  at + n

(* d * 10^e, d > 0 of at most p digits, as %.pg lays it out, trailing zeros gone; then ".0" or e and the exponent. *)
let layout b at d e p =
  let d = ref d and e = ref e in
  while !d mod 10000 = 0 do d := !d / 10000; e := !e + 4 done;
  while !d mod 10 = 0 do d := !d / 10; incr e done;
  let n = ref 1 and t = ref 10 in
  while !d >= !t do incr n; t := !t * 10 done;
  let d = !d and n = !n in
  let x = !e + n - 1 in
  if x < -4 || x >= p then begin
    (* d.ddde-7: the digits one place right, the first moved back before the point. *)
    digits b (at + 1) n d;
    Bytes.set b at (Bytes.get b (at + 1));
    let at = if n > 1 then (Bytes.set b (at + 1) '.'; at + n + 1) else at + 1 in
    Bytes.set b at 'e';
    let at = if x < 0 then (Bytes.set b (at + 1) '-'; at + 2) else at + 1 in
    let ax = abs x in
    let w = if ax >= 100 then 3 else if ax >= 10 then 2 else 1 in
    digits b at w ax;
    at + w
  end
  else if x < 0 then begin
    let at = zeros b (put b at "0.") (-x - 1) in
    digits b at n d;
    at + n
  end
  else if n <= x + 1 then begin
    digits b at n d;
    put b (zeros b (at + n) (x + 1 - n)) ".0"
  end
  else begin
    digits b (at + 1) n d;
    Bytes.blit b (at + 1) b at (x + 1);
    Bytes.set b (at + x + 1) '.';
    at + n + 1
  end

let rec width f = if f = 0 then 0 else 1 + width (f lsr 1)

let write b at x =
  let bits = Int64.bits_of_float x in
  let biased = Int64.to_int (Int64.shift_right_logical bits 52) land 0x7ff in
  let f = Int64.to_int bits land ((1 lsl 52) - 1) in
  if biased = 0x7ff then put b at (if f <> 0 then "nan" else if Int64.compare bits 0L < 0 then "-inf" else "inf")
  else begin
    let at = if Int64.compare bits 0L < 0 then (Bytes.set b at '-'; at + 1) else at in
    if biased = 0 && f = 0 then put b at "0.0"
    else begin
      let sub = biased = 0 in
      let s = if sub then 53 - width f else 0 in
      let mv = (if sub then f lsl s else f lor (1 lsl 52)) lsl 2 in
      let e2 = if sub then -1076 - s else biased - 1077 in
      let mp = mv + if sub then 1 lsl (s + 1) else 2 in
      let mm = mv - if sub then 1 lsl (s + 1) else if f = 0 && biased > 1 then 1 else 2 in
      let up = e2 >= 0 in
      let q = if up then log10_pow2 e2 - (if e2 > 3 then 1 else 0) else log10_pow5 (-e2) - (if e2 < -1 then 1 else 0) in
      let e10 = if up then q else q + e2 in
      let idx = if up then q else -e2 - q in
      let j = if up then q - e2 + 124 + pow5_bits q else q + 125 - pow5_bits idx in
      let tab = if up then Pow5.inv else Pow5.pow5 in
      let t0 = limb tab idx 0 and t1 = limb tab idx 1 and t2 = limb tab idx 2 in
      let t3 = limb tab idx 3 and t4 = limb tab idx 4 in
      let vr = mul_shift t0 t1 t2 t3 t4 mv j in
      let vp = mul_shift t0 t1 t2 t3 t4 mp j in
      let vm = mul_shift t0 t1 t2 t3 t4 mm j in
      let even = f land 1 = 0 and xr = exact up q mv in
      let lo = if even && exact up q mm then vm else vm + 1 in
      let hi = if (not even) && exact up q mp then vp - 1 else vp in
      let l = if vr >= 1_000_000_000_000_000_000 then 19 else if vr >= 100_000_000_000_000_000 then 18 else 17 in
      let d15 = round vr xr (l - 15) in
      if fits lo hi (l - 15) d15 then layout b at d15 (e10 + l - 15) 15
      else begin
        let d16 = round vr xr (l - 16) in
        if fits lo hi (l - 16) d16 then layout b at d16 (e10 + l - 16) 16
        else layout b at (round vr xr (l - 17)) (e10 + l - 17) 17
      end
    end
  end
