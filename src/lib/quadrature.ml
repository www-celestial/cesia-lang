(* The engine of std/quad: QUADPACK's adaptive integration (Piessens, de Doncker-Kapenga, Überhuber and Kahaner 1983),
   QAGS on one piece, QAGP on the pieces between given points, QAGI on (0, 1] after x = a + (1 - t) / t, with Wynn's
   epsilon algorithm on the sums. Native code, so that the only Cesia its loop runs is f: the same method in Cesia spent
   six times as long on its own steps as on f. std/quad.ce checks the arguments and makes the Ok or the Err, with its
   message, from what [engine] gives. Each step does what QUADPACK's code does, in the same order, so that the values are
   the same to the last bit. *)
open Types

let eps = epsilon_float
let tiny = Float.min_float
let huge = Float.max_float
let depth = 50

(* The Gauss–Kronrod rules on [-1, 1]: the middle, then the positive points x of the pairs -x and x, in the order QUADPACK
   adds them (for 21 points, Gauss's first, then Kronrod's own; for 15, from the end inwards), with the weights of
   Kronrod's rule and of Gauss's, 0 at Kronrod's own points. Computed for Cesia from Stieltjes's polynomial in exact
   rational numbers, its zeros to 100 digits, rounded here to 22 digits; tests/lang/quad.ce checks them against Laurie's
   algorithm. *)
let x21 =
  [| 0.0; 0.9739065285171717200780; 0.8650633666889845107321; 0.6794095682990244062343; 0.4333953941292471907993;
     0.1488743389816312108848; 0.9956571630258080807355; 0.9301574913557082260012; 0.7808177265864168970637;
     0.5627571346686046833390; 0.2943928627014601981311 |]

let w21 =
  [| 0.1494455540029169056649; 0.03255816230796472747882; 0.07503967481091995276704; 0.1093871588022976418992;
     0.1347092173114733259281; 0.1477391049013384913748; 0.01169463886737187427806; 0.05475589657435199603138;
     0.09312545458369760553507; 0.1234919762620658510780; 0.1427759385770600807971 |]

let g21 =
  [| 0.0; 0.06667134430868813759357; 0.1494513491505805931458; 0.2190863625159820439955; 0.2692667193099963550912;
     0.2955242247147528701739; 0.0; 0.0; 0.0; 0.0; 0.0 |]

(* The places in x21 of the points in their own order, from the end inwards: QUADPACK adds the terms of I_asc so. *)
let natural21 = [| 0; 6; 1; 7; 2; 8; 3; 9; 4; 10; 5 |]
let natural15 = [| 0; 1; 2; 3; 4; 5; 6; 7 |]

let x15 =
  [| 0.0; 0.9914553711208126392069; 0.9491079123427585245262; 0.8648644233597690727897; 0.7415311855993944398639;
     0.5860872354676911302941; 0.4058451513773971669066; 0.2077849550078984676007 |]

let w15 =
  [| 0.2094821410847278280130; 0.02293532201052922496373; 0.06309209262997855329070; 0.1047900103222501838399;
     0.1406532597155259187452; 0.1690047266392679028266; 0.1903505780647854099133; 0.2044329400752988924142 |]

let g15 =
  [| 0.4179591836734693877551; 0.0; 0.1294849661688696932706; 0.0; 0.2797053914892766679015; 0.0;
     0.3818300505051189449504; 0.0 |]

(* An end of [engine] other than QUADPACK's own: 6, f gave no finite number at the place, the value given; 7, the sums
   of a rule overflow near the place; 8, f / t² overflows at the place, t given. *)
exception Stop of int * float * t

(* Where the loop of [engine] stands: going on, done with an answer, or at the end of QUADPACK's loop. *)
type ending = Running | Answer of t | Ended

let finite x = x -. x = 0.
let max2 a b = if a >= b then a else b

(* f at x, a finite float, else the engine stops there. *)
let at ctx f x =
  match Compile.call_back ctx f [| Float x |] with
  | Float y when finite y -> y
  | Int i -> float_of_int i
  | v -> raise (Stop (6, x, v))

(* A rule's answer on its piece, from ys, f at the middle then at the points -x, and zs, 0 then f at the points x: its
   integral, QUADPACK's error estimate, the integral of |f| and that of |f - its mean|. A pair is one term,
   f(-x) + f(x), so that an odd f centred on 0 gives exactly 0. The estimate is I_asc min(1, (200 |K - G| / I_asc)^1.5),
   at least 50 eps times the integral of |f|. *)
let estimate ys zs n h kw gw natural place =
  let resk = ref 0. and resg = ref 0. and sum_abs = ref 0. in
  for i = 0 to n - 1 do
    let p = ys.(i) +. zs.(i) in
    resk := !resk +. (kw.(i) *. p);
    resg := !resg +. (gw.(i) *. p);
    sum_abs := !sum_abs +. (kw.(i) *. (Float.abs ys.(i) +. Float.abs zs.(i)))
  done;
  let half = 0.5 *. !resk and asc = ref 0. in
  for j = 0 to n - 1 do
    let i = natural.(j) in
    let d = if i = 0 then Float.abs (ys.(0) -. half) else Float.abs (ys.(i) -. half) +. Float.abs (zs.(i) -. half) in
    asc := !asc +. (kw.(i) *. d)
  done;
  let ah = Float.abs h in
  let resabs = !sum_abs *. ah and resasc = !asc *. ah in
  if not (finite resabs && finite resasc) then raise (Stop (7, place, Missing));
  let err = ref (Float.abs ((!resk -. !resg) *. h)) in
  if resasc <> 0. && !err <> 0. then begin
    let r = 200. *. !err /. resasc in
    err := resasc *. if r < 1. then r ** 1.5 else 1.
  end;
  if resabs > tiny /. (50. *. eps) then err := max2 (50. *. eps *. resabs) !err;
  !resk *. h, !err, resabs, resasc

(* x for a t of (0, 1]: from + (1 - t) / t, or from - (1 - t) / t for way -1. *)
let place way from t = if way = -1 then from -. ((1. -. t) /. t) else from +. ((1. -. t) /. t)

(* The rule of 21 points on [a, b] (way 0), or of 15 on [a, b] inside (0, 1] for an infinite bound: f(x) / t², with
   f(x) + f(-x) for way 2. ys and zs are scratch. *)
let rule ctx f way from ys zs a b =
  let c = 0.5 *. (a +. b) and h = 0.5 *. (b -. a) in
  if way = 0 then begin
    ys.(0) <- at ctx f c;
    zs.(0) <- 0.;
    for i = 1 to 10 do
      let hx = h *. x21.(i) in
      ys.(i) <- at ctx f (c -. hx);
      zs.(i) <- at ctx f (c +. hx)
    done;
    estimate ys zs 11 h w21 g21 natural21 c
  end
  else begin
    let value t =
      let x = place way from t in
      let y = at ctx f x in
      let y = if way = 2 then y +. at ctx f (-.x) else y in
      let v = y /. t /. t in
      if finite v then v else raise (Stop (8, x, Float t))
    in
    ys.(0) <- value c;
    zs.(0) <- 0.;
    for i = 1 to 7 do
      let ht = h *. x15.(i) in
      ys.(i) <- value (c -. ht);
      zs.(i) <- value (c +. ht)
    done;
    estimate ys zs 8 h w15 g15 natural15 (place way from c)
  end

(* One step of Wynn's epsilon algorithm (1956) on the sequence of sums: table.(1..n) holds the two last ascending
   diagonals of its even columns, interleaved, table.(n) the newest sum. The new diagonal comes from Wynn's cross rule
   (1966), 1/(N - C) + 1/(S - C) = 1/(W - C) + 1/(E - C), which links the even columns alone. Of the new elements, the
   value is the one that moved least from its neighbours; from the fourth call, the error is its distance to the last
   three values, and at least 5 eps of it. A column whose elements agree to the last bits ends the table; so does one
   where the rule would divide by about 0. At most [depth] sums. Gives the value, its error and the new n. *)
let epsilon table n last3 calls =
  let err = ref huge and res = ref table.(n) and n = ref n in
  if !n < 3 then !res, max2 !err (5. *. eps *. Float.abs !res), !n
  else begin
    let num = !n and newelm = (!n - 1) / 2 in
    table.(num + 2) <- table.(num);
    table.(num) <- huge;
    let k1 = ref num and i = ref 1 and over = ref false and converged = ref false in
    while (not !over) && !i <= newelm do
      let e0 = table.(!k1 - 2) and e1 = table.(!k1 - 1) and e2 = table.(!k1 + 2) in
      let e1abs = Float.abs e1 in
      let delta2 = e2 -. e1 and delta3 = e1 -. e0 in
      let err2 = Float.abs delta2 and err3 = Float.abs delta3 in
      let tol2 = max2 (Float.abs e2) e1abs *. eps and tol3 = max2 e1abs (Float.abs e0) *. eps in
      if err2 <= tol2 && err3 <= tol3 then begin
        res := e2;
        err := err2 +. err3;
        over := true;
        converged := true
      end
      else begin
        let e3 = table.(!k1) in
        table.(!k1) <- e1;
        let delta1 = e1 -. e3 in
        let err1 = Float.abs delta1 and tol1 = max2 e1abs (Float.abs e3) *. eps in
        let close = err1 <= tol1 || err2 <= tol2 || err3 <= tol3 in
        let ss = if close then 0. else (1. /. delta1) +. (1. /. delta2) -. (1. /. delta3) in
        if close || Float.abs (ss *. e1) <= 1e-4 then begin
          n := !i + !i - 1;
          over := true
        end
        else begin
          let r = e1 +. (1. /. ss) in
          table.(!k1) <- r;
          k1 := !k1 - 2;
          let e = err2 +. Float.abs (r -. e2) +. err3 in
          if e <= !err then begin
            err := e;
            res := r
          end;
          incr i
        end
      end
    done;
    if !converged then !res, max2 !err (5. *. eps *. Float.abs !res), num
    else begin
      if !n = depth then n := (2 * (depth / 2)) - 1;
      let ib = ref (if num mod 2 = 0 then 2 else 1) in
      for _ = 1 to newelm + 1 do
        table.(!ib) <- table.(!ib + 2);
        ib := !ib + 2
      done;
      if num <> !n then begin
        let from = num - !n + 1 in
        for j = 1 to !n do
          table.(j) <- table.(from + j - 1)
        done
      end;
      if !calls < 4 then begin
        last3.(!calls - 1) <- !res;
        err := huge
      end
      else begin
        err := Float.abs (!res -. last3.(2)) +. Float.abs (!res -. last3.(1)) +. Float.abs (!res -. last3.(0));
        last3.(0) <- last3.(1);
        last3.(1) <- last3.(2);
        last3.(2) <- !res
      end;
      !res, max2 !err (5. *. eps *. Float.abs !res), !n
    end
  end

(* The order of the pieces by error after maxerr was cut: maxerr holds the half of larger error, last the other; only
   the first [top] places are kept in order, as many as can still be cut before limit. Gives the new nrmax. 1-based. *)
let insert order el limit last maxerr nrmax =
  if last <= 2 then begin
    order.(1) <- 1;
    order.(2) <- 2;
    nrmax
  end
  else begin
    let errmax = el.(maxerr) and nrmax = ref nrmax in
    while !nrmax > 1 && errmax > el.(order.(!nrmax - 1)) do
      order.(!nrmax) <- order.(!nrmax - 1);
      decr nrmax
    done;
    let top = if last > (limit / 2) + 2 then limit + 3 - last else last in
    let errmin = el.(last) and i = ref (!nrmax + 1) in
    while !i <= top - 1 && errmax < el.(order.(!i)) do
      order.(!i - 1) <- order.(!i);
      incr i
    done;
    if !i > top - 1 then begin
      order.(top - 1) <- maxerr;
      order.(top) <- last
    end
    else begin
      order.(!i - 1) <- maxerr;
      let k = ref (top - 1) in
      while !k >= !i && errmin >= el.(order.(!k)) do
        order.(!k + 1) <- order.(!k);
        decr k
      done;
      order.(!k + 1) <- last
    end;
    !nrmax
  end

(* engine(f, way, from, ends, rtol, atol, limit, byLevel): [code, value, error, calls, pieces, tolerance, place, given].
   code 0: the tolerance met; 1 to 5, QUADPACK's flags: the limit, roundoff, a bad place, the extrapolation, divergence;
   6 to 8, as [Stop]. *)
let engine ctx (a : t array) =
  let num v = match v with Float x -> x | Int i -> float_of_int i | _ -> nan in
  let f = a.(0) and way = (match a.(1) with Int w -> w | _ -> 0) and from = num a.(2) in
  let ends = match a.(3) with Array s -> Array.init (s.rows * s.cols) (fun k -> num (Value.elt s k)) | _ -> [| 0.; 1. |] in
  let rtol = num a.(4) and atol = num a.(5) and limit = (match a.(6) with Int l -> l | _ -> 1) in
  let by_level = match a.(7) with True -> true | _ -> false in
  let n0 = Array.length ends - 1 in
  let points = if way = 0 then 21 else if way = 2 then 30 else 15 in
  let calls last = (points * n0) + (2 * points * (last - n0)) in
  let errbnd = ref 0. in
  let answer code v e calls last place given =
    Arrays.list [| Int code; Float v; Float e; Int calls; Int last; Float !errbnd; Float place; given |]
  in
  let ys = Array.make 11 0. and zs = Array.make 11 0. in
  let size = ref (max (n0 + 1) (min limit 16)) in
  Runtime.reserve ctx (6 * !size);
  let al = ref (Array.make (!size + 1) 0.) and bl = ref (Array.make (!size + 1) 0.) in
  let rl = ref (Array.make (!size + 1) 0.) and el = ref (Array.make (!size + 1) 0.) in
  let lv = ref (Array.make (!size + 1) 0) and order = ref (Array.make (!size + 1) 0) in
  let area = ref nan and errsum = ref infinity in
  try
    let first = ref 0. and first_err = ref 0. and defabs = ref 0. and resasc = ref 0. in
    let saturated = Array.make (n0 + 1) false in
    for i = 1 to n0 do
      Runtime.pay ctx points;
      let r, e, ab, asc = rule ctx f way from ys zs ends.(i - 1) ends.(i) in
      !al.(i) <- ends.(i - 1);
      !bl.(i) <- ends.(i);
      !rl.(i) <- r;
      !el.(i) <- e;
      first := !first +. r;
      first_err := !first_err +. e;
      defabs := !defabs +. ab;
      resasc := asc;
      !order.(i) <- i;
      saturated.(i) <- e = asc && e <> 0.
    done;
    errsum := !first_err;
    if by_level then begin
      errsum := 0.;
      for i = 1 to n0 do
        if saturated.(i) then !el.(i) <- !first_err;
        errsum := !errsum +. !el.(i)
      done;
      (* QUADPACK's sort of the first pieces of QAGP, the larger errors first. *)
      for i = 1 to n0 - 1 do
        let big = ref !order.(i) and at = ref i in
        for j = i + 1 to n0 do
          if !el.(!order.(j)) >= !el.(!big) then begin
            big := !order.(j);
            at := j
          end
        done;
        if !at <> i then begin
          !order.(!at) <- !order.(i);
          !order.(i) <- !big
        end
      done
    end;
    let ier = ref 0 in
    errbnd := max2 atol (rtol *. Float.abs !first);
    if !first_err <= 100. *. eps *. !defabs && !first_err > !errbnd then ier := 2;
    let done_ =
      if by_level then !first_err <= !errbnd
      else (!first_err <= !errbnd && !first_err <> !resasc) || !first_err = 0.
    in
    if done_ then answer 0 !first !first_err (points * n0) n0 0. Missing
    else begin
      if !ier = 0 && limit = n0 then ier := 1;
      if !ier <> 0 then answer !ier !first !first_err (points * n0) n0 0. Missing
      else begin
        let table = Array.make (depth + 3) 0. and last3 = Array.make 3 0. and ecalls = ref 0 in
        table.(1) <- !first;
        let count = ref (if by_level then 1 else 2) in
        let maxerr = ref !order.(1) in
        let errmax = ref !el.(!maxerr) in
        area := !first;
        let abserr = ref huge and best = ref !first and nrmax = ref 1 and ktmin = ref 0 in
        let extrap = ref false and noext = ref false in
        let iroff1 = ref 0 and iroff2 = ref 0 and iroff3 = ref 0 and ierro = ref 0 in
        let ksgn = if Float.abs !first >= (1. -. (50. *. eps)) *. !defabs then 1 else -1 in
        let erlarg = ref !errsum and ertest = ref !errbnd and correc = ref 0. in
        let small = ref (Float.abs (ends.(n0) -. ends.(0)) *. 0.375) and levmax = ref 1 in
        let last = ref n0 and cut = ref 0. and finished = ref Running in
        let large k = if by_level then !lv.(k) + 1 <= !levmax else Float.abs (!bl.(k) -. !al.(k)) > !small in
        while !finished = Running do
          incr last;
          if !last > !size then begin
            let grow fill a = Array.append a (Array.make !size fill) in
            Runtime.reserve ctx (6 * !size);
            al := grow 0. !al;
            bl := grow 0. !bl;
            rl := grow 0. !rl;
            el := grow 0. !el;
            lv := grow 0 !lv;
            order := grow 0 !order;
            size := !size + !size
          end;
          let al = !al and bl = !bl and rl = !rl and el = !el and lv = !lv and order = !order and last_ = !last in
          let a1 = al.(!maxerr) and b1 = 0.5 *. (al.(!maxerr) +. bl.(!maxerr)) in
          let a2 = b1 and b2 = bl.(!maxerr) in
          cut := b1;
          let level = lv.(!maxerr) + 1 and erlast = !errmax in
          Runtime.pay ctx (2 * points);
          let r1, e1, _, asc1 = rule ctx f way from ys zs a1 b1 in
          let r2, e2, _, asc2 = rule ctx f way from ys zs a2 b2 in
          let area12 = r1 +. r2 and erro12 = e1 +. e2 in
          errsum := !errsum +. erro12 -. !errmax;
          area := !area +. area12 -. rl.(!maxerr);
          if not (asc1 = e1 || asc2 = e2) then begin
            if Float.abs (rl.(!maxerr) -. area12) <= 1.0e-5 *. Float.abs area12 && erro12 >= 0.99 *. !errmax then
              if !extrap then incr iroff2 else incr iroff1;
            if last_ > 10 && erro12 > !errmax then incr iroff3
          end;
          lv.(!maxerr) <- level;
          lv.(last_) <- level;
          errbnd := max2 atol (rtol *. Float.abs !area);
          if !iroff1 + !iroff2 >= 10 || !iroff3 >= 20 then ier := 2;
          if !iroff2 >= 5 then ierro := 3;
          if last_ = limit then ier := 1;
          if max2 (Float.abs a1) (Float.abs b2) <= (1. +. (100. *. eps)) *. (Float.abs a2 +. (1000. *. tiny)) then ier := 4;
          (* The piece of larger error keeps the place of the one cut; the other is the new last. *)
          if e2 > e1 then begin
            al.(!maxerr) <- a2;
            al.(last_) <- a1;
            bl.(last_) <- b1;
            rl.(!maxerr) <- r2;
            rl.(last_) <- r1;
            el.(!maxerr) <- e2;
            el.(last_) <- e1
          end
          else begin
            al.(last_) <- a2;
            bl.(!maxerr) <- b1;
            bl.(last_) <- b2;
            rl.(!maxerr) <- r1;
            rl.(last_) <- r2;
            el.(!maxerr) <- e1;
            el.(last_) <- e2
          end;
          nrmax := insert order el limit last_ !maxerr !nrmax;
          maxerr := order.(!nrmax);
          errmax := el.(!maxerr);
          if !errsum <= !errbnd then begin
            let s = ref 0. in
            for k = 1 to last_ do
              s := !s +. rl.(k)
            done;
            finished := Answer (answer 0 !s !errsum (calls last_) last_ 0. Missing)
          end
          else if !ier <> 0 then finished := Ended
          else if (not by_level) && last_ = 2 then begin
            small := Float.abs (ends.(1) -. ends.(0)) *. 0.375;
            erlarg := !errsum;
            ertest := !errbnd;
            table.(2) <- !area
          end
          else if not !noext then begin
            erlarg := !erlarg -. erlast;
            if (if by_level then level + 1 <= !levmax else Float.abs (b1 -. a1) > !small) then erlarg := !erlarg +. erro12;
            let go_on = ref false in
            if not !extrap then
              if large !maxerr then go_on := true
              else begin
                extrap := true;
                nrmax := 2
              end;
            if (not !go_on) && !ierro <> 3 && !erlarg > !ertest then begin
              (* The smallest pieces have the largest errors: cut the larger ones first, from the largest error down, among
                 those that can still be cut before limit. *)
              let top = if last_ > 2 + (limit / 2) then limit + 3 - last_ else last_ in
              let k = ref !nrmax and stop = ref false in
              while (not !stop) && !k <= top do
                maxerr := order.(!nrmax);
                errmax := el.(!maxerr);
                if large !maxerr then begin
                  go_on := true;
                  stop := true
                end
                else begin
                  incr nrmax;
                  incr k
                end
              done
            end;
            if not !go_on then begin
              incr count;
              table.(!count) <- !area;
              let stop = ref false in
              if (not by_level) || !count > 2 then begin
                incr ecalls;
                let v, e, n = epsilon table !count last3 ecalls in
                count := n;
                incr ktmin;
                if !ktmin > 5 && !abserr < 1.0e-3 *. !errsum then ier := 5;
                if e < !abserr then begin
                  ktmin := 0;
                  abserr := e;
                  best := v;
                  correc := !erlarg;
                  ertest := max2 atol (rtol *. Float.abs v);
                  if (if by_level then !abserr < !ertest else !abserr <= !ertest) then stop := true
                end;
                if !count = 1 then noext := true;
                if !ier = 5 then stop := true
              end;
              if !stop then finished := Ended
              else begin
                maxerr := order.(1);
                errmax := el.(!maxerr);
                nrmax := 1;
                extrap := false;
                small := !small *. 0.5;
                incr levmax;
                erlarg := !errsum
              end
            end
          end
        done;
        match !finished with
        | Answer v -> v
        | Running | Ended ->
          (* The end: the extrapolated value, or the sum of the pieces, whichever has the smaller relative error; then
             QUADPACK's test of divergence, that the two agree within a factor of 100 and that the error is below the
             area. *)
          let last = !last and rl = !rl in
          let sum = ref (!abserr = huge) and divergence = ref false in
          if not !sum then
            if !ier + !ierro = 0 then divergence := true
            else begin
              if !ierro = 3 then abserr := !abserr +. !correc;
              if !ier = 0 then ier := 3;
              if !best <> 0. && !area <> 0. then begin
                sum := !abserr /. Float.abs !best > !errsum /. Float.abs !area;
                divergence := not !sum
              end
              else if !abserr > !errsum then sum := true
              else if !area <> 0. then divergence := true
            end;
          if !divergence && not (ksgn = -1 && max2 (Float.abs !best) (Float.abs !area) <= !defabs *. 0.01) then
            if 0.01 > !best /. !area || !best /. !area > 100. || !errsum > Float.abs !area then ier := 6;
          if !sum then begin
            let s = ref 0. in
            for k = 1 to last do
              s := !s +. rl.(k)
            done;
            best := !s;
            abserr := !errsum
          end;
          if !ier > 2 then decr ier;
          let near = if way = 0 then !cut else if way = 2 then place 1 0. !cut else place way from !cut in
          answer !ier !best !abserr (calls last) last near Missing
      end
    end
  with Stop (code, x, v) -> answer code !area !errsum 0 0 x v

let natives = [ "engine", Native.nat "engine" 8 8 engine ]
