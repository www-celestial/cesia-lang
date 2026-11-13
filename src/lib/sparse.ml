(* The kernels of std/sparse: the approximate minimum degree ordering of Amestoy, Davis and Duff (1996), and LU's
   factorization, left-looking with the depth-first search of Gilbert and Peierls (1988), as Davis (2006, ch. 6) writes
   it. Matrices are in compressed columns, from 0. Every input is checked first, so
   that no index leaves its array, whatever the caller gives; [pay] counts the work as it goes, so that a limit of steps
   or a stop is met within a column, and [reserve] the memory before each large array. *)

let valid ~m ~n (p : int array) (i : int array) =
  Array.length p = n + 1
  && p.(0) = 0
  && p.(n) = Array.length i
  && (let ok = ref true in
      for j = 0 to n - 1 do
        if p.(j + 1) < p.(j) then ok := false
      done;
      Array.iter (fun r -> if r < 0 || r >= m then ok := false) i;
      !ok)

let permutation n (q : int array) =
  Array.length q = n
  && (let seen = Array.make n false and ok = ref true in
      Array.iter (fun j -> if j < 0 || j >= n || seen.(j) then ok := false else seen.(j) <- true) q;
      !ok)

(* The pattern of a + a' without its diagonal, each cell once, from the columns [p], [i] of an n x n pattern. *)
let symmetric n p i =
  let tp = Array.make (n + 1) 0 in
  Array.iter (fun r -> tp.(r + 1) <- tp.(r + 1) + 1) i;
  for j = 0 to n - 1 do
    tp.(j + 1) <- tp.(j + 1) + tp.(j)
  done;
  let ti = Array.make (Array.length i) 0 and next = Array.sub tp 0 n in
  for j = 0 to n - 1 do
    for q = p.(j) to p.(j + 1) - 1 do
      let r = i.(q) in
      ti.(next.(r)) <- j;
      next.(r) <- next.(r) + 1
    done
  done;
  let mark = Array.make n (-1) and cp = Array.make (n + 1) 0 in
  let each stamp j f =
    mark.(j) <- stamp;
    let see r = if mark.(r) <> stamp then begin mark.(r) <- stamp; f r end in
    for q = p.(j) to p.(j + 1) - 1 do see i.(q) done;
    for q = tp.(j) to tp.(j + 1) - 1 do see ti.(q) done
  in
  for j = 0 to n - 1 do
    each j j (fun _ -> cp.(j + 1) <- cp.(j + 1) + 1)
  done;
  for j = 0 to n - 1 do
    cp.(j + 1) <- cp.(j + 1) + cp.(j)
  done;
  let ci = Array.make cp.(n) 0 and at = ref 0 in
  for j = 0 to n - 1 do
    each (n + j) j (fun r -> ci.(!at) <- r; incr at)
  done;
  cp, ci

(* The order of the n unknowns of a square pattern, by approximate minimum degree on the pattern of a + a': perm.(k) is
   the k-th eliminated. The quotient graph of the paper: each variable keeps its elements, then its variables, in one
   list of [iw]; an element its variables. Degrees are the paper's bound |Ai| + Σ |Le \ Lk| + |Lk \ i|, each |Le \ Lk| as
   w.(e) - mark; supervariables are found by a hash, elements inside Lk absorbed, a variable left with Lk alone
   eliminated with k, and a variable of degree over 10 √n put aside and ordered last. The order is a postorder of the
   tree of elements. *)
let amd ~pay n p i =
  let cp, ci = symmetric n p i in
  let nz = cp.(n) in
  let iw = ref (Array.make (nz + (nz / 5) + (2 * n) + 1) 0) in
  Array.blit ci 0 !iw 0 nz;
  let pfree = ref nz in
  let pe = Array.make (n + 1) 0 and len = Array.make (n + 1) 0 and elen = Array.make (n + 1) 0 in
  let nv = Array.make (n + 1) 1 and degree = Array.make (n + 1) 0 and w = Array.make (n + 1) 1 in
  let parent = Array.make (n + 1) (-1) and head = Array.make (n + 1) (-1) and next = Array.make (n + 1) (-1) in
  let last = Array.make (n + 1) (-1) and hhead = Array.make (n + 1) (-1) and saved = Array.make (n + 1) 0 in
  for v = 0 to n - 1 do
    pe.(v) <- cp.(v);
    len.(v) <- cp.(v + 1) - cp.(v);
    degree.(v) <- len.(v)
  done;
  nv.(n) <- 0;
  let dense = Float.min (Float.max 16. (10. *. sqrt (float n))) (float n -. 2.) in
  let nel = ref 0 and mindeg = ref n in
  for v = 0 to n - 1 do
    let d = degree.(v) in
    if d = 0 then begin
      elen.(v) <- -2;
      incr nel;
      w.(v) <- 0
    end
    else if float d > dense then begin
      nv.(v) <- 0;
      elen.(v) <- -1;
      incr nel;
      parent.(v) <- n;
      nv.(n) <- nv.(n) + 1
    end
    else begin
      let h = head.(d) in
      if h <> -1 then last.(h) <- v;
      next.(v) <- h;
      head.(d) <- v;
      if d < !mindeg then mindeg := d
    end
  done;
  let top = ref 1 and lemax = ref 0 in
  while !nel < n do
    (* 1. A variable of least degree. *)
    let k = ref head.(!mindeg) in
    while !k = -1 do
      incr mindeg;
      k := head.(!mindeg)
    done;
    let k = !k in
    let h = next.(k) in
    if h <> -1 then last.(h) <- -1;
    head.(!mindeg) <- h;
    let elenk = elen.(k) and nvk = ref nv.(k) in
    nel := !nel + !nvk;
    (* 2. Room for Lk past the lists, at most degree.(k) entries: else the lists are moved together, and iw grows if
       that is not enough. *)
    if elenk > 0 && !pfree + degree.(k) > Array.length !iw then begin
      let a = !iw in
      for v = 0 to n - 1 do
        if len.(v) > 0 && (elen.(v) >= 0 || (elen.(v) = -2 && w.(v) <> 0)) then begin
          saved.(v) <- a.(pe.(v));
          a.(pe.(v)) <- -(v + 1)
        end
      done;
      let src = ref 0 and dst = ref 0 in
      while !src < !pfree do
        let j = -a.(!src) - 1 in
        if j >= 0 then begin
          a.(!dst) <- saved.(j);
          pe.(j) <- !dst;
          incr dst;
          incr src;
          for _ = 2 to len.(j) do
            a.(!dst) <- a.(!src);
            incr dst;
            incr src
          done
        end
        else incr src
      done;
      pfree := !dst;
      if !pfree + degree.(k) > Array.length a then begin
        let bigger = Array.make ((2 * Array.length a) + degree.(k)) 0 in
        Array.blit a 0 bigger 0 !pfree;
        iw := bigger
      end
    end;
    let iw = !iw in
    (* 3. Lk: the variables of the elements of k and of k's own list, each once; the elements of k are absorbed. *)
    let dk = ref 0 in
    nv.(k) <- - !nvk;
    let p = ref pe.(k) in
    let pk1 = if elenk = 0 then !p else !pfree in
    let pk2 = ref pk1 in
    for k1 = 1 to elenk + 1 do
      let e, pj, ln =
        if k1 <= elenk then begin
          let e = iw.(!p) in
          incr p;
          e, pe.(e), len.(e)
        end
        else k, !p, len.(k) - elenk
      in
      for q = pj to pj + ln - 1 do
        let v = iw.(q) in
        let nvi = nv.(v) in
        if nvi > 0 then begin
          dk := !dk + nvi;
          nv.(v) <- -nvi;
          iw.(!pk2) <- v;
          incr pk2;
          let ni = next.(v) and li = last.(v) in
          if ni <> -1 then last.(ni) <- li;
          if li <> -1 then next.(li) <- ni else head.(degree.(v)) <- ni
        end
      done;
      if e <> k then begin
        parent.(e) <- k;
        w.(e) <- 0
      end
    done;
    if elenk <> 0 then pfree := !pk2;
    degree.(k) <- !dk;
    pe.(k) <- pk1;
    len.(k) <- !pk2 - pk1;
    elen.(k) <- -2;
    (* 4. |Le \ Lk| for each element e of a variable of Lk, as w.(e) - mark. *)
    let mark = !top + 1 in
    for pk = pk1 to !pk2 - 1 do
      let v = iw.(pk) in
      let eln = elen.(v) in
      if eln > 0 then begin
        let nvi = -nv.(v) in
        let wnvi = mark - nvi in
        for q = pe.(v) to pe.(v) + eln - 1 do
          let e = iw.(q) in
          let we = w.(e) in
          if we >= mark then w.(e) <- we - nvi else if we <> 0 then w.(e) <- degree.(e) + wnvi
        done
      end
    done;
    top := mark + !lemax;
    (* 5. The degree of each variable of Lk, its lists pruned, k first among its elements; an element inside Lk is
       absorbed, and a variable left with k alone is eliminated with it. *)
    for pk = pk1 to !pk2 - 1 do
      let v = iw.(pk) in
      let p1 = pe.(v) in
      let p2 = p1 + elen.(v) - 1 in
      let pn = ref p1 and hash = ref 0 and d = ref 0 in
      for q = p1 to p2 do
        let e = iw.(q) in
        if w.(e) <> 0 then begin
          let dext = w.(e) - mark in
          if dext > 0 then begin
            d := !d + dext;
            iw.(!pn) <- e;
            incr pn;
            hash := !hash + e
          end
          else begin
            parent.(e) <- k;
            w.(e) <- 0
          end
        end
      done;
      elen.(v) <- !pn - p1 + 1;
      let p3 = !pn in
      for q = p2 + 1 to p1 + len.(v) - 1 do
        let j = iw.(q) in
        let nvj = nv.(j) in
        if nvj > 0 then begin
          d := !d + nvj;
          iw.(!pn) <- j;
          incr pn;
          hash := !hash + j
        end
      done;
      if !d = 0 then begin
        parent.(v) <- k;
        let nvi = -nv.(v) in
        dk := !dk - nvi;
        nvk := !nvk + nvi;
        nel := !nel + nvi;
        nv.(v) <- 0;
        elen.(v) <- -1
      end
      else begin
        if !d < degree.(v) then degree.(v) <- !d;
        iw.(!pn) <- iw.(p3);
        iw.(p3) <- iw.(p1);
        iw.(p1) <- k;
        len.(v) <- !pn - p1 + 1;
        let h = !hash mod n in
        next.(v) <- hhead.(h);
        hhead.(h) <- v;
        last.(v) <- h
      end
    done;
    degree.(k) <- !dk;
    if !dk > !lemax then lemax := !dk;
    (* 6. Supervariables: two variables of Lk with the same elements and variables become one. *)
    for pk = pk1 to !pk2 - 1 do
      let v = iw.(pk) in
      if nv.(v) < 0 then begin
        let h = last.(v) in
        let i = ref hhead.(h) in
        hhead.(h) <- -1;
        while !i <> -1 && next.(!i) <> -1 do
          let ln = len.(!i) and eln = elen.(!i) in
          incr top;
          for q = pe.(!i) + 1 to pe.(!i) + ln - 1 do
            w.(iw.(q)) <- !top
          done;
          let jlast = ref !i and j = ref next.(!i) in
          while !j <> -1 do
            let same = ref (len.(!j) = ln && elen.(!j) = eln) and q = ref (pe.(!j) + 1) in
            while !same && !q <= pe.(!j) + ln - 1 do
              if w.(iw.(!q)) <> !top then same := false;
              incr q
            done;
            if !same then begin
              parent.(!j) <- !i;
              nv.(!i) <- nv.(!i) + nv.(!j);
              nv.(!j) <- 0;
              elen.(!j) <- -1;
              j := next.(!j);
              next.(!jlast) <- !j
            end
            else begin
              jlast := !j;
              j := next.(!j)
            end
          done;
          i := next.(!i)
        done
      end
    done;
    (* 7. Back into the lists of degrees; Lk keeps its principal variables. *)
    let p = ref pk1 in
    for pk = pk1 to !pk2 - 1 do
      let v = iw.(pk) in
      let nvi = -nv.(v) in
      if nvi > 0 then begin
        nv.(v) <- nvi;
        let d = min (degree.(v) + !dk - nvi) (n - !nel - nvi) in
        let h = head.(d) in
        if h <> -1 then last.(h) <- v;
        next.(v) <- h;
        last.(v) <- -1;
        head.(d) <- v;
        if d < !mindeg then mindeg := d;
        degree.(v) <- d;
        iw.(!p) <- v;
        incr p
      end
    done;
    nv.(k) <- !nvk;
    len.(k) <- !p - pk1;
    if len.(k) = 0 then w.(k) <- 0;
    if elenk <> 0 then pfree := !p;
    pay (!pk2 - pk1 + 1)
  done;
  (* The postorder of the tree: each node after its children, the elements of a node before its variables, and the
     variables put aside, children of node n, last. *)
  let child = Array.make (n + 1) (-1) and sibling = Array.make (n + 1) (-1) in
  for j = n - 1 downto 0 do
    if nv.(j) = 0 then begin
      sibling.(j) <- child.(parent.(j));
      child.(parent.(j)) <- j
    end
  done;
  for e = n - 1 downto 0 do
    if nv.(e) > 0 && parent.(e) <> -1 then begin
      sibling.(e) <- child.(parent.(e));
      child.(parent.(e)) <- e
    end
  done;
  let perm = Array.make n 0 and stack = Array.make (n + 1) 0 and count = ref 0 in
  for root = 0 to n do
    if parent.(root) = -1 && nv.(root) > 0 then begin
      let depth = ref 0 in
      stack.(0) <- root;
      while !depth >= 0 do
        let x = stack.(!depth) in
        let c = child.(x) in
        if c = -1 then begin
          decr depth;
          if x < n then begin
            perm.(!count) <- x;
            incr count
          end
        end
        else begin
          child.(x) <- sibling.(c);
          incr depth;
          stack.(!depth) <- c
        end
      done
    end
  done;
  if !count <> n then invalid_arg "Sparse.amd";
  perm

(* The LU factorization of a q: p a q = L U, L lower triangular with ones on its diagonal, which is not kept, U upper
   triangular with its diagonal last in each column, both in columns, their rows in the order of the pivots, and pinv,
   where each row of a went; or [None] when a column has no pivot above 0. Column k is a sparse triangular solve with
   the columns before it, its pattern first found by a depth-first search, so the work is that of the arithmetic. The
   pivot is the largest candidate, or the diagonal when it is at least tol times it. *)
let lu ~pay ~reserve n ap ai (ax : floatarray) q tol =
  let room = (4 * Array.length ai) + n in
  reserve (4 * room);
  let lp = Array.make (n + 1) 0 and up = Array.make (n + 1) 0 in
  let li = ref (Array.make room 0) and lx = ref (Float.Array.make room 0.) in
  let ui = ref (Array.make room 0) and ux = ref (Float.Array.make room 0.) in
  let pinv = Array.make n (-1) and x = Float.Array.make n 0. and xi = Array.make n 0 in
  let seen = Array.make n (-1) and stack = Array.make n 0 and pos = Array.make n 0 in
  let lfree = ref 0 and ufree = ref 0 and work = ref 0 in
  let grow (i : int array ref) (v : floatarray ref) used =
    if used + n + 1 > Array.length !i then begin
      let m = (2 * Array.length !i) + n + 1 in
      reserve (2 * m);
      let i' = Array.make m 0 and v' = Float.Array.make m 0. in
      Array.blit !i 0 i' 0 used;
      Float.Array.blit !v 0 v' 0 used;
      i := i';
      v := v'
    end
  in
  match
    for k = 0 to n - 1 do
      lp.(k) <- !lfree;
      up.(k) <- !ufree;
      grow li lx !lfree;
      grow ui ux !ufree;
      let li = !li and lx = !lx and ui = !ui and ux = !ux and col = q.(k) and top = ref n in
      for r = ap.(col) to ap.(col + 1) - 1 do
        if seen.(ai.(r)) <> k then begin
          let depth = ref 0 in
          stack.(0) <- ai.(r);
          while !depth >= 0 do
            let j = stack.(!depth) in
            let jj = pinv.(j) in
            if seen.(j) <> k then begin
              seen.(j) <- k;
              pos.(!depth) <- (if jj = -1 then 0 else lp.(jj))
            end;
            let pend = if jj = -1 then 0 else lp.(jj + 1) and at = ref pos.(!depth) and pushed = ref false in
            while !at < pend && not !pushed do
              let c = li.(!at) in
              incr at;
              if seen.(c) <> k then begin
                pos.(!depth) <- !at;
                incr depth;
                stack.(!depth) <- c;
                pushed := true
              end
            done;
            if not !pushed then begin
              decr depth;
              decr top;
              xi.(!top) <- j
            end
          done
        end
      done;
      for r = ap.(col) to ap.(col + 1) - 1 do
        Float.Array.set x ai.(r) (Float.Array.get ax r)
      done;
      for t = !top to n - 1 do
        let j = xi.(t) in
        let jj = pinv.(j) in
        if jj <> -1 then begin
          let xj = Float.Array.get x j in
          for r = lp.(jj) to lp.(jj + 1) - 1 do
            let c = li.(r) in
            Float.Array.set x c (Float.Array.get x c -. (Float.Array.get lx r *. xj))
          done;
          work := !work + lp.(jj + 1) - lp.(jj)
        end
      done;
      let ipiv = ref (-1) and big = ref (-1.) in
      for t = !top to n - 1 do
        let i = xi.(t) in
        if pinv.(i) = -1 then begin
          let v = Float.abs (Float.Array.get x i) in
          if v > !big then begin
            big := v;
            ipiv := i
          end
        end
        else begin
          ui.(!ufree) <- pinv.(i);
          Float.Array.set ux !ufree (Float.Array.get x i);
          incr ufree
        end
      done;
      if !ipiv = -1 || not (!big > 0.) then raise_notrace Exit;
      if pinv.(col) = -1 && Float.abs (Float.Array.get x col) >= tol *. !big then ipiv := col;
      let pivot = Float.Array.get x !ipiv in
      ui.(!ufree) <- k;
      Float.Array.set ux !ufree pivot;
      incr ufree;
      pinv.(!ipiv) <- k;
      for t = !top to n - 1 do
        let i = xi.(t) in
        if pinv.(i) = -1 then begin
          li.(!lfree) <- i;
          Float.Array.set lx !lfree (Float.Array.get x i /. pivot);
          incr lfree
        end;
        Float.Array.set x i 0.
      done;
      work := !work + n - !top;
      if !work > 1 lsl 20 then begin
        pay !work;
        work := 0
      end
    done
  with
  | () ->
    lp.(n) <- !lfree;
    up.(n) <- !ufree;
    let li = Array.init !lfree (fun r -> pinv.(!li.(r))) in
    Some (lp, li, Float.Array.sub !lx 0 !lfree, up, Array.sub !ui 0 !ufree, Float.Array.sub !ux 0 !ufree, pinv)
  | exception Exit -> None

(* Factorizations by supernodes, multifrontal: Liu (1992) for the method, Ashcraft and Grimes (1989) for the relaxed
   supernodes. A supernode is a run of columns of L that share their pattern below the diagonal block (Liu, Ng and
   Peyton 1993); its block of L, rows x columns, is dense. Each supernode gathers in a dense *front* the cells of a in
   its columns and the updates its children in the elimination tree left, factors its columns, and leaves the update
   of the rows below, its Schur complement, to its parent; the dense work goes to BLAS when the machine has it. *)

let at f m r c = { Kernels.data = f; offset = r + (c * m); ld = m }

(* Below this many products a call to BLAS costs more than it saves; from [wide] on, a second thread pays. More threads
   than that made the medium products of fronts 5 to 30 times slower on a busy machine. *)
let least = 1024
let wide = 1 lsl 27

(* out - x y', or out - x y when not [trans]: BLAS for large blocks, else this loop by columns of out, four columns of x
   at a time. *)
let update ~pay ~rows ~cols ~inner ~trans out x y =
  let work = rows * cols * inner in
  pay work;
  if
    rows > 0 && cols > 0 && inner > 0
    && not (work >= least && !Kernels.gemm ~rows ~cols ~inner ~trans ~sub:true ~threads:(if work < wide then 1 else 2) out x y)
  then begin
    let { Kernels.data = od; offset = oo; ld = ol } = out and { Kernels.data = xd; offset = xo; ld = xl } = x in
    let { Kernels.data = yd; offset = yo; ld = yl } = y in
    let yat j p = if trans then yo + j + (p * yl) else yo + p + (j * yl) in
    for j = 0 to cols - 1 do
      let o = oo + (j * ol) and p = ref 0 in
      while !p + 3 < inner do
        let b0 = Float.Array.get yd (yat j !p) and b1 = Float.Array.get yd (yat j (!p + 1)) in
        let b2 = Float.Array.get yd (yat j (!p + 2)) and b3 = Float.Array.get yd (yat j (!p + 3)) in
        let s0 = xo + (!p * xl) in
        let s1 = s0 + xl in
        let s2 = s1 + xl in
        let s3 = s2 + xl in
        for i = 0 to rows - 1 do
          Float.Array.set od (o + i)
            (Float.Array.get od (o + i)
            -. ((Float.Array.get xd (s0 + i) *. b0) +. (Float.Array.get xd (s1 + i) *. b1)
               +. (Float.Array.get xd (s2 + i) *. b2) +. (Float.Array.get xd (s3 + i) *. b3)))
        done;
        p := !p + 4
      done;
      while !p < inner do
        let b = Float.Array.get yd (yat j !p) and s = xo + (!p * xl) in
        if b <> 0. then
          for i = 0 to rows - 1 do
            Float.Array.set od (o + i) (Float.Array.get od (o + i) -. (Float.Array.get xd (s + i) *. b))
          done;
        incr p
      done
    done
  end

(* Cholesky of the columns j0 to j1 - 1 of a front f of order m, by columns, rows j0 to m - 1, once the columns before
   j0 have updated them: one column at a time for 4 columns or fewer, else the left half, its update of the right half,
   then the right half (Gustavson 1997), so that nearly all the work is a product of blocks. False when a pivot is not
   above 0. *)
let rec chol_columns ~pay f m j0 j1 =
  if j1 - j0 <= 4 then begin
    pay ((m - j0) * (j1 - j0) * (j1 - j0) / 2);
    let j = ref j0 in
    while !j < j1 && Float.Array.get f ((!j * m) + !j) > 0. do
      let cj = !j * m in
      let d = sqrt (Float.Array.get f (cj + !j)) in
      let r = 1. /. d in
      Float.Array.set f (cj + !j) d;
      for i = !j + 1 to m - 1 do
        Float.Array.set f (cj + i) (Float.Array.get f (cj + i) *. r)
      done;
      for c = !j + 1 to j1 - 1 do
        let cc = c * m and l = Float.Array.get f (cj + c) in
        if l <> 0. then
          for i = c to m - 1 do
            Float.Array.set f (cc + i) (Float.Array.get f (cc + i) -. (Float.Array.get f (cj + i) *. l))
          done
      done;
      incr j
    done;
    !j = j1
  end
  else begin
    let h = (j0 + j1) / 2 in
    chol_columns ~pay f m j0 h
    && begin
      update ~pay ~rows:(m - h) ~cols:(j1 - h) ~inner:(h - j0) ~trans:true (at f m h h) (at f m h j0) (at f m h j0);
      chol_columns ~pay f m h j1
    end
  end

(* The rows j0 to j1 - 1 of the columns c0 to c1 - 1 of a front, solved by the lower triangle of its block (j0..j1 - 1)²
   with ones on its diagonal: U's part beside LU's pivots. *)
let rec unit_solve ~pay f m j0 j1 c0 c1 =
  if j1 - j0 <= 4 then begin
    pay ((c1 - c0) * (j1 - j0) * (j1 - j0) / 2);
    for c = c0 to c1 - 1 do
      let cc = c * m in
      for j = j0 to j1 - 1 do
        let x = Float.Array.get f (cc + j) and cj = j * m in
        if x <> 0. then
          for i = j + 1 to j1 - 1 do
            Float.Array.set f (cc + i) (Float.Array.get f (cc + i) -. (Float.Array.get f (cj + i) *. x))
          done
      done
    done
  end
  else begin
    let h = (j0 + j1) / 2 in
    unit_solve ~pay f m j0 h c0 c1;
    update ~pay ~rows:(j1 - h) ~cols:(c1 - c0) ~inner:(h - j0) ~trans:false (at f m h c0) (at f m h j0) (at f m j0 c0);
    unit_solve ~pay f m h j1 c0 c1
  end

(* LU of the columns j0 to j1 - 1 of a front, rows j0 to m - 1, as chol_columns, the pivot of each column from the
   rows j to kp - 1 that the front holds whole: the row in place when its cell is at least tol times the largest of
   the column (rows j to m - 1), else the largest of those rows when it passes that test; a swap moves whole rows of
   the front, and [order] with them. False when no row passes, or the column holds only zeros. *)
let rec lu_columns ~pay f m kp tol order j0 j1 =
  if j1 - j0 <= 4 then begin
    pay ((m - j0) * (j1 - j0) * (j1 - j0) / 2);
    let j = ref j0 and ok = ref true in
    while !ok && !j < j1 do
      let jj = !j in
      let cj = jj * m in
      let big = ref 0. and best = ref jj and top = ref (-1.) in
      for i = jj to m - 1 do
        let v = Float.abs (Float.Array.get f (cj + i)) in
        if v > !big then big := v;
        if i < kp && v > !top then begin
          top := v;
          best := i
        end
      done;
      let limit = tol *. !big in
      let p = if Float.abs (Float.Array.get f (cj + jj)) >= limit then jj else !best in
      if !big > 0. && Float.abs (Float.Array.get f (cj + p)) >= limit then begin
        if p <> jj then begin
          for c = 0 to m - 1 do
            let a = Float.Array.get f ((c * m) + p) in
            Float.Array.set f ((c * m) + p) (Float.Array.get f ((c * m) + jj));
            Float.Array.set f ((c * m) + jj) a
          done;
          let t = order.(p) in
          order.(p) <- order.(jj);
          order.(jj) <- t
        end;
        let r = 1. /. Float.Array.get f (cj + jj) in
        for i = jj + 1 to m - 1 do
          Float.Array.set f (cj + i) (Float.Array.get f (cj + i) *. r)
        done;
        for c = jj + 1 to j1 - 1 do
          let cc = c * m in
          let u = Float.Array.get f (cc + jj) in
          if u <> 0. then
            for i = jj + 1 to m - 1 do
              Float.Array.set f (cc + i) (Float.Array.get f (cc + i) -. (Float.Array.get f (cj + i) *. u))
            done
        done;
        incr j
      end
      else ok := false
    done;
    !ok
  end
  else begin
    let h = (j0 + j1) / 2 in
    lu_columns ~pay f m kp tol order j0 h
    && begin
      unit_solve ~pay f m j0 h h j1;
      update ~pay ~rows:(m - h) ~cols:(j1 - h) ~inner:(h - j0) ~trans:false (at f m h h) (at f m h j0) (at f m j0 h);
      lu_columns ~pay f m kp tol order h j1
    end
  end

(* Which cells [gather] keeps, renamed (r, c), and where: [Lower] those with r >= c, at (r, c); [Below] those with r > c,
   at (c, r), the rows of the lower triangle as columns; [Above] those with r < c, at (c, r), the rows of the upper
   triangle; [Both] all, at (max, min), the lower triangle of the pattern of a + a'. *)
type side = Lower | Below | Above | Both

let column side r c =
  match side with Lower -> if r >= c then c else -1 | Below -> if r > c then r else -1 | Above -> if r < c then r else -1 | Both -> min r c

let row side r c = match side with Lower -> r | Below | Above -> c | Both -> max r c

(* Two passes of a counting sort: the cells of an n x n matrix (columns p, rows i, values x if any) that [side] keeps,
   their rows and columns renamed by pinv, in columns. *)
let gather n p i (x : floatarray option) pinv side =
  let cp = Array.make (n + 1) 0 in
  for c = 0 to n - 1 do
    let pc = pinv.(c) in
    for q = p.(c) to p.(c + 1) - 1 do
      let col = column side pinv.(i.(q)) pc in
      if col >= 0 then cp.(col + 1) <- cp.(col + 1) + 1
    done
  done;
  for j = 0 to n - 1 do
    cp.(j + 1) <- cp.(j + 1) + cp.(j)
  done;
  let ci = Array.make cp.(n) 0 and at = Array.sub cp 0 n in
  let cx = match x with Some _ -> Float.Array.make cp.(n) 0. | None -> Float.Array.make 0 0. in
  for c = 0 to n - 1 do
    let pc = pinv.(c) in
    for q = p.(c) to p.(c + 1) - 1 do
      let r = pinv.(i.(q)) in
      let col = column side r pc in
      if col >= 0 then begin
        let t = at.(col) in
        ci.(t) <- row side r pc;
        (match x with Some x -> Float.Array.set cx t (Float.Array.get x q) | None -> ());
        at.(col) <- t + 1
      end
    done
  done;
  cp, ci, cx


(* What the numbers of a factorization by supernodes need: the order, the supernodes, the parent of each, its
   children, the rows of each and the sizes of the arrays, all known before any of those is allocated. *)
type symbolic = {
  n : int;
  fperm : int array;  (* the unknown eliminated k-th *)
  rank : int array;  (* the postorder: the new name of each column of the pattern *)
  super : int array;  (* the first column of each supernode, then n *)
  sparent : int array;
  hd : int array;  (* the first child of each supernode, nx the next *)
  nx : int array;
  rp : int array;  (* where the rows of each supernode start, then their count *)
  widest : int;  (* the most rows of a front *)
  front : int;  (* the most cells of a front, widest^2 *)
  peak : int;  (* the most cells that the updates waiting for their parents hold *)
  stored : int;  (* the cells of the blocks m x k of L *)
  counted : bool;  (* false when a size went past 2^52 *)
}

(* The supernodes of the factor of the symmetric pattern whose lower triangle (cp, ci) is that of p a p', perm being p.
   The elimination tree (Liu's algorithm, with the path compressed through ancestor), its postorder, the count of each
   column of L, each row of L being the subtree of the tree that its cells reach (Davis 2006, ch. 4); then the
   fundamental supernodes, and the relaxed ones. No sum can overflow: each term is at most n^2 <= 2^53 and a sum past
   2^52 stops the count. *)
let analyse ~pay n cp ci perm =
  let up, ui, _ = gather n cp ci None (Array.init n Fun.id) Below in
  let parent = Array.make n (-1) and ancestor = Array.make n (-1) in
  for k = 0 to n - 1 do
    for q = up.(k) to up.(k + 1) - 1 do
      let j = ref ui.(q) in
      while !j <> -1 && !j < k do
        let next = ancestor.(!j) in
        ancestor.(!j) <- k;
        if next = -1 then parent.(!j) <- k;
        j := next
      done
    done
  done;
  let head = Array.make n (-1) and next = Array.make n (-1) in
  for j = n - 1 downto 0 do
    if parent.(j) <> -1 then begin
      next.(j) <- head.(parent.(j));
      head.(parent.(j)) <- j
    end
  done;
  let post = Array.make n 0 and filled = ref 0 and stack = ancestor in
  for root = 0 to n - 1 do
    if parent.(root) = -1 then begin
      let top = ref 0 in
      stack.(0) <- root;
      while !top >= 0 do
        let j = stack.(!top) in
        match head.(j) with
        | -1 ->
          decr top;
          post.(!filled) <- j;
          incr filled
        | c ->
          head.(j) <- next.(c);
          incr top;
          stack.(!top) <- c
      done
    end
  done;
  let count = Array.make n 0 and mark = head and work = ref 0 in
  Array.fill mark 0 n (-1);
  for k = 0 to n - 1 do
    mark.(k) <- k;
    count.(k) <- count.(k) + 1;
    for q = up.(k) to up.(k + 1) - 1 do
      let j = ref ui.(q) in
      while mark.(!j) <> k do
        count.(!j) <- count.(!j) + 1;
        mark.(!j) <- k;
        j := parent.(!j)
      done
    done;
    work := !work + count.(k);
    if !work > 1 lsl 20 then begin
      pay !work;
      work := 0
    end
  done;
  pay !work;
  (* The columns renamed in postorder: each subtree is then a run of columns. *)
  let rank = Array.make n 0 in
  Array.iteri (fun k j -> rank.(j) <- k) post;
  let fperm = Array.init n (fun k -> perm.(post.(k))) in
  let par = Array.init n (fun k -> match parent.(post.(k)) with -1 -> -1 | j -> rank.(j)) in
  let count = Array.init n (fun k -> count.(post.(k))) in
  (* Fundamental supernodes: column j joins j - 1 when j is its parent, its only child, and its pattern is that of j - 1
     less j - 1 (Liu, Ng and Peyton 1993). *)
  let kids = Array.make n 0 in
  Array.iter (fun j -> if j <> -1 then kids.(j) <- kids.(j) + 1) par;
  let first = Array.make (n + 1) n and nf = ref 0 in
  for j = 0 to n - 1 do
    if j = 0 || par.(j - 1) <> j || count.(j - 1) <> count.(j) + 1 || kids.(j) > 1 then begin
      first.(!nf) <- j;
      incr nf
    end
  done;
  let nf = !nf in
  (* Relaxed supernodes (Ashcraft and Grimes 1989): a supernode s merges with s + 1 when s + 1 is its parent and the
     zeros the merge stores stay few, from the top of the tree down, with the thresholds of CHOLMOD (Chen, Davis, Hager
     and Rajamanickam 2008): 4 columns or fewer always; else at most 80 % zeros up to 16 columns, 10 % up to 48, 5 %
     beyond. [merged] leads each merged supernode to the one it went into. *)
  let where = Array.make n 0 in
  for s = 0 to nf - 1 do
    for j = first.(s) to first.(s + 1) - 1 do
      where.(j) <- s
    done
  done;
  let merged = Array.make nf (-1) in
  let find s =
    let x = ref s in
    while merged.(!x) <> -1 do
      let p = merged.(!x) in
      if merged.(p) <> -1 then merged.(!x) <- merged.(p);
      x := merged.(!x)
    done;
    !x
  in
  let cols = Array.init nf (fun s -> first.(s + 1) - first.(s)) and lnz = Array.init nf (fun s -> count.(first.(s))) in
  let zeros = Array.make nf 0 in
  for s = nf - 2 downto 0 do
    let l = par.(first.(s + 1) - 1) in
    if l <> -1 && find where.(l) = s + 1 then begin
      let k0 = cols.(s) and k1 = cols.(s + 1) in
      let ns = k0 + k1 and fresh = k0 * (lnz.(s + 1) + k0 - lnz.(s)) in
      let total = zeros.(s + 1) + fresh in
      let z = float total /. ((float ns *. float (ns + 1) /. 2.) +. (float ns *. float (lnz.(s + 1) - k1))) in
      if ns <= 4 || fresh = 0 || (ns <= 16 && z < 0.8) || (ns <= 48 && z < 0.1) || z < 0.05 then begin
        merged.(s + 1) <- s;
        zeros.(s) <- total;
        lnz.(s) <- k0 + lnz.(s + 1);
        cols.(s) <- ns
      end
    end
  done;
  let ns = Array.fold_left (fun c t -> if t = -1 then c + 1 else c) 0 merged in
  let super = Array.make (ns + 1) n and g = ref 0 in
  for s = 0 to nf - 1 do
    if merged.(s) = -1 then begin
      super.(!g) <- first.(s);
      incr g
    end
  done;
  for g = 0 to ns - 1 do
    for j = super.(g) to super.(g + 1) - 1 do
      where.(j) <- g
    done
  done;
  let sparent = Array.init ns (fun g -> match par.(super.(g + 1) - 1) with -1 -> -1 | j -> where.(j)) in
  let hd = Array.make ns (-1) and nx = Array.make ns (-1) in
  for g = ns - 1 downto 0 do
    if sparent.(g) <> -1 then begin
      nx.(g) <- hd.(sparent.(g));
      hd.(sparent.(g)) <- g
    end
  done;
  (* Each supernode's rows: its columns, then the rows below its last column, as many as that column's count less 1. *)
  let rp = Array.make (ns + 1) 0 and big = 1 lsl 52 and widest = ref 0 and peak = ref 0 and depth = ref 0 in
  let stored = ref 0 and g = ref 0 in
  while !g < ns && !stored <= big && !depth <= big do
    let k = super.(!g + 1) - super.(!g) in
    let m = k + count.(super.(!g + 1) - 1) - 1 in
    rp.(!g + 1) <- rp.(!g) + m;
    stored := !stored + (m * k);
    widest := max !widest m;
    let c = ref hd.(!g) in
    while !c <> -1 do
      let u = rp.(!c + 1) - rp.(!c) - (super.(!c + 1) - super.(!c)) in
      depth := !depth - (u * u);
      c := nx.(!c)
    done;
    if sparent.(!g) <> -1 then depth := !depth + ((m - k) * (m - k));
    peak := max !peak !depth;
    incr g
  done;
  { n; fperm; rank; super; sparent; hd; nx; rp; widest = !widest; front = !widest * !widest; peak = !peak; stored = !stored;
    counted = !g = ns }

(* The rows of each supernode: its columns in order, then the rows below them in no order, from the cells of the lower
   triangle (ap, ai), renamed, and the rows its children update. *)
let rows_of s ap ai =
  let rows = Array.make s.rp.(Array.length s.super - 1) 0 and stamp = Array.make s.n (-1) and ok = ref true in
  for g = 0 to Array.length s.super - 2 do
    let f0 = s.super.(g) and l = s.super.(g + 1) - 1 and r = ref s.rp.(g) in
    for j = f0 to l do
      stamp.(j) <- g;
      rows.(!r) <- j;
      incr r
    done;
    let add row =
      if stamp.(row) <> g then begin
        stamp.(row) <- g;
        if !r < s.rp.(g + 1) && row > l then rows.(!r) <- row else ok := false;
        incr r
      end
    in
    for j = f0 to l do
      for q = ap.(j) to ap.(j + 1) - 1 do
        add ai.(q)
      done
    done;
    let c = ref s.hd.(g) in
    while !c <> -1 do
      for t = s.rp.(!c) + s.super.(!c + 1) - s.super.(!c) to s.rp.(!c + 1) - 1 do
        add rows.(t)
      done;
      c := s.nx.(!c)
    done;
    if !r <> s.rp.(g + 1) then ok := false
  done;
  if not !ok then invalid_arg "Sparse.rows_of";
  rows

(* The multifrontal loop: for each supernode in order, its front of order m made 0 and its rows numbered, [assemble]
   adding the cells of a, the updates of its children taken from the stack, [factor] of its k columns (false stops all),
   then [keep] storing its blocks and its update pushed: the lower triangle of the last m - k rows and columns of the
   front when [half], else all of them. *)
let frontal ~pay s rows ~half ~assemble ~factor ~keep =
  let ns = Array.length s.super - 1 in
  let f = Float.Array.make (max 1 s.front) 0. and stack = Float.Array.make (max 1 s.peak) 0. in
  let ids = Array.make (ns + 1) 0 and offs = Array.make (ns + 1) 0 and map = Array.make s.n 0 in
  let rel = Array.make (max 1 s.widest) 0 in
  let top = ref 0 and g = ref 0 in
  while !g < ns && begin
    let g = !g in
    let k = s.super.(g + 1) - s.super.(g) and r0 = s.rp.(g) and m = s.rp.(g + 1) - s.rp.(g) in
    for t = 0 to m - 1 do
      map.(rows.(r0 + t)) <- t
    done;
    if half then
      for c = 0 to m - 1 do
        Float.Array.fill f ((c * m) + c) (m - c) 0.
      done
    else Float.Array.fill f 0 (m * m) 0.;
    assemble g f m map;
    while !top > 0 && s.sparent.(ids.(!top - 1)) = g do
      decr top;
      let c = ids.(!top) and o = offs.(!top) in
      let s0 = s.rp.(c) + s.super.(c + 1) - s.super.(c) in
      let u = s.rp.(c + 1) - s0 in
      for t = 0 to u - 1 do
        rel.(t) <- map.(rows.(s0 + t))
      done;
      for q = 0 to u - 1 do
        let cq = rel.(q) and src = o + (q * u) in
        if half then
          (* Rows in no order: a cell of the lower triangle of the update goes to the lower triangle of the front. *)
          for p = q to u - 1 do
            let rq = rel.(p) in
            let at = if rq >= cq then rq + (cq * m) else cq + (rq * m) in
            Float.Array.set f at (Float.Array.get f at +. Float.Array.get stack (src + p))
          done
        else begin
          let cm = cq * m in
          for p = 0 to u - 1 do
            let at = cm + rel.(p) in
            Float.Array.set f at (Float.Array.get f at +. Float.Array.get stack (src + p))
          done
        end
      done
    done;
    factor g f m k
    && begin
      keep g f m k;
      if s.sparent.(g) <> -1 then begin
        let u = m - k and o = offs.(!top) in
        if half then
          for q = 0 to u - 1 do
            Float.Array.blit f (((k + q) * m) + k + q) stack (o + (q * u) + q) (u - q)
          done
        else
          for q = 0 to u - 1 do
            Float.Array.blit f (((k + q) * m) + k) stack (o + (q * u)) u
          done;
        ids.(!top) <- g;
        offs.(!top + 1) <- o + (u * u);
        incr top
      end;
      pay (m * m);
      true
    end
  end
  do
    incr g
  done;
  !g = ns

type cholesky_factor = {
  s : symbolic;
  rows : int array;  (* each supernode's rows, from rows_of *)
  lp : int array;  (* where the block of each supernode starts in [lx] *)
  lx : floatarray;  (* each block of L by columns, rows x columns, 0 above its diagonal *)
}

type lu_factor = {
  ls : symbolic;
  cols : int array;  (* each supernode's columns of U: as rows_of gives them *)
  pivots : int array;  (* its rows of L, the pivots first, in their order *)
  llp : int array;  (* the block m x k of each supernode in [llx]: L below the diagonal, U on and above it *)
  llx : floatarray;
  ulp : int array;  (* the block k x (m - k) of U right of the pivots, in [ulx] *)
  ulx : floatarray;
}

type factor = Chol of cholesky_factor | Lu of lu_factor

type outcome = Factor of factor | Failed | Memory of int

let size = function Chol f -> Float.Array.length f.lx | Lu f -> Float.Array.length f.llx + Float.Array.length f.ulx

let offsets s each =
  let ns = Array.length s.super - 1 in
  let p = Array.make (ns + 1) 0 in
  for g = 0 to ns - 1 do
    let k = s.super.(g + 1) - s.super.(g) and m = s.rp.(g + 1) - s.rp.(g) in
    p.(g + 1) <- p.(g) + each m k
  done;
  p

(* The words of the arrays [s] counted (L's blocks, a front, the stack, the rows), plus [more]: [Some words] past the
   limit. *)
let over s ~limit more =
  let words = float s.stored +. float s.front +. float s.peak +. float s.rp.(Array.length s.super - 1) +. more in
  if not s.counted || words > float limit then Some (if s.counted then int_of_float words else 1 lsl 52) else None

let words s more = s.stored + s.front + s.peak + s.rp.(Array.length s.super - 1) + more

let order n perm =
  let pinv = Array.make n 0 in
  Array.iteri (fun k j -> pinv.(j) <- k) perm;
  pinv

(* p a p' = L L' for a symmetric n x n matrix a in columns (p, i, x) and the order perm of AMD, or [Failed] when a
   pivot is not above 0, or [Memory words] when L and the work would take more than [limit] words. Only the cells of
   p a p' on and below its diagonal are read, so that the pattern and the numbers agree whatever the caller gives. *)
let cholesky ~pay ~reserve ~limit n p i (x : floatarray) perm =
  let cp, ci, cx = gather n p i (Some x) (order n perm) Lower in
  let s = analyse ~pay n cp ci perm in
  let more = (6 * Array.length ci) + (12 * n) in
  match over s ~limit (float more) with
  | Some w -> Memory w
  | None ->
    reserve (words s more);
    (* A cell below the diagonal is in a column of which its row is an ancestor in the tree: renamed in postorder, it
       stays below the diagonal. *)
    let ap, ai, ax = gather n cp ci (Some cx) s.rank Lower in
    let rows = rows_of s ap ai in
    let lp = offsets s (fun m k -> m * k) in
    let lx = Float.Array.make lp.(Array.length lp - 1) 0. in
    let assemble g f m map =
      for j = s.super.(g) to s.super.(g + 1) - 1 do
        let o = (j - s.super.(g)) * m in
        for q = ap.(j) to ap.(j + 1) - 1 do
          let at = o + map.(ai.(q)) in
          Float.Array.set f at (Float.Array.get f at +. Float.Array.get ax q)
        done
      done
    in
    let factor _ f m k =
      chol_columns ~pay f m 0 k
      && begin
        let c = ref k in
        while !c < m do
          let w = min 128 (m - !c) in
          update ~pay ~rows:(m - !c) ~cols:w ~inner:k ~trans:true (at f m !c !c) (at f m !c 0) (at f m !c 0);
          c := !c + w
        done;
        true
      end
    in
    let keep g f m k =
      for j = 0 to k - 1 do
        Float.Array.blit f ((j * m) + j) lx (lp.(g) + (j * m) + j) (m - j)
      done
    in
    if frontal ~pay s rows ~half:true ~assemble ~factor ~keep then Factor (Chol { s; rows; lp; lx }) else Failed

(* p a q = L U for an n x n matrix a whose pattern is nearly symmetric, q the order perm of AMD on a + a', by the
   supernodes of the pattern of a + a': each front pivots inside the rows it holds whole, by threshold pivoting with
   tol. [Failed] when a column finds no pivot there that passes the test: Gilbert and Peierls's LU, which can take any
   row, then does the work. *)
let front_lu ~pay ~reserve ~limit n p i (x : floatarray) perm tol =
  let pinv = order n perm in
  let cp, ci, _ = gather n p i None pinv Both in
  let s = analyse ~pay n cp ci perm in
  let llp = offsets s (fun m k -> m * k) and ulp = offsets s (fun m k -> k * (m - k)) in
  let ns = Array.length s.super - 1 in
  let more = ulp.(ns) + s.rp.(ns) + (4 * Array.length ci) + (6 * p.(n)) + (12 * n) in
  match over s ~limit (float more) with
  | Some w -> Memory w
  | None ->
    reserve (words s more);
    let renamed = Array.map (fun k -> s.rank.(k)) pinv in
    let ap, ai, _ = gather n cp ci None s.rank Lower in
    let cols = rows_of s ap ai in
    let lo, li, lx = gather n p i (Some x) renamed Lower and uo, ui, ux = gather n p i (Some x) renamed Above in
    let pivots = Array.copy cols and order = Array.make (max 1 s.widest) 0 in
    let llx = Float.Array.make llp.(ns) 0. and ulx = Float.Array.make ulp.(ns) 0. in
    let assemble g f m map =
      for j = s.super.(g) to s.super.(g + 1) - 1 do
        let jm = map.(j) in
        for q = lo.(j) to lo.(j + 1) - 1 do
          let at = (jm * m) + map.(li.(q)) in
          Float.Array.set f at (Float.Array.get f at +. Float.Array.get lx q)
        done;
        for q = uo.(j) to uo.(j + 1) - 1 do
          let at = (map.(ui.(q)) * m) + jm in
          Float.Array.set f at (Float.Array.get f at +. Float.Array.get ux q)
        done
      done
    in
    let factor g f m k =
      for t = 0 to k - 1 do
        order.(t) <- t
      done;
      lu_columns ~pay f m k tol order 0 k
      && begin
        unit_solve ~pay f m 0 k k m;
        let c = ref k in
        while !c < m do
          let w = min 128 (m - !c) in
          update ~pay ~rows:(m - k) ~cols:w ~inner:k ~trans:false (at f m k !c) (at f m k 0) (at f m 0 !c);
          c := !c + w
        done;
        let r0 = s.rp.(g) in
        for t = 0 to k - 1 do
          pivots.(r0 + t) <- cols.(r0 + order.(t))
        done;
        true
      end
    in
    let keep g f m k =
      Float.Array.blit f 0 llx llp.(g) (m * k);
      for c = k to m - 1 do
        Float.Array.blit f (c * m) ulx (ulp.(g) + ((c - k) * k)) k
      done
    in
    if frontal ~pay s cols ~half:false ~assemble ~factor ~keep then Factor (Lu { ls = s; cols; pivots; llp; llx; ulp; ulx })
    else Failed

(* x of a x = b: for Cholesky, x = p' (L' \ (L \ (p b))); for LU, x = q (U \ (L \ (p b))), each block a column at a
   time. *)
let solve fac (b : floatarray) =
  let nothing _ = () and vec data offset ld = { Kernels.data; offset; ld } in
  match fac with
  | Chol { s; rows; lp; lx } ->
    let n = s.n and super = s.super and rp = s.rp in
    let y = Float.Array.init n (fun k -> Float.Array.get b s.fperm.(k)) and t = Float.Array.make (max 1 s.widest) 0. in
    for g = 0 to Array.length super - 2 do
      let f0 = super.(g) and k = super.(g + 1) - super.(g) and r0 = rp.(g) and m = rp.(g + 1) - rp.(g) in
      let u = m - k in
      for j = 0 to k - 1 do
        let o = lp.(g) + (j * m) in
        let yj = Float.Array.get y (f0 + j) /. Float.Array.get lx (o + j) in
        Float.Array.set y (f0 + j) yj;
        for q = j + 1 to k - 1 do
          Float.Array.set y (f0 + q) (Float.Array.get y (f0 + q) -. (Float.Array.get lx (o + q) *. yj))
        done
      done;
      if u * k >= least then begin
        Float.Array.fill t 0 u 0.;
        update ~pay:nothing ~rows:u ~cols:1 ~inner:k ~trans:false (vec t 0 u) (vec lx (lp.(g) + k) m) (vec y f0 k);
        for q = 0 to u - 1 do
          let i = rows.(r0 + k + q) in
          Float.Array.set y i (Float.Array.get y i +. Float.Array.get t q)
        done
      end
      else
        for j = 0 to k - 1 do
          let o = lp.(g) + (j * m) and yj = Float.Array.get y (f0 + j) in
          for q = k to m - 1 do
            let i = rows.(r0 + q) in
            Float.Array.set y i (Float.Array.get y i -. (Float.Array.get lx (o + q) *. yj))
          done
        done
    done;
    for g = Array.length super - 2 downto 0 do
      let f0 = super.(g) and k = super.(g + 1) - super.(g) and r0 = rp.(g) and m = rp.(g + 1) - rp.(g) in
      let u = m - k in
      if u * k >= least then begin
        for q = 0 to u - 1 do
          Float.Array.set t q (Float.Array.get y rows.(r0 + k + q))
        done;
        update ~pay:nothing ~rows:1 ~cols:k ~inner:u ~trans:false (vec y f0 1) (vec t 0 1) (vec lx (lp.(g) + k) m)
      end
      else
        for j = 0 to k - 1 do
          let o = lp.(g) + (j * m) in
          let acc = ref (Float.Array.get y (f0 + j)) in
          for q = k to m - 1 do
            acc := !acc -. (Float.Array.get lx (o + q) *. Float.Array.get y rows.(r0 + q))
          done;
          Float.Array.set y (f0 + j) !acc
        done;
      for j = k - 1 downto 0 do
        let o = lp.(g) + (j * m) in
        let acc = ref (Float.Array.get y (f0 + j)) in
        for q = j + 1 to k - 1 do
          acc := !acc -. (Float.Array.get lx (o + q) *. Float.Array.get y (f0 + q))
        done;
        Float.Array.set y (f0 + j) (!acc /. Float.Array.get lx (o + j))
      done
    done;
    let x = Float.Array.make n 0. in
    Array.iteri (fun k j -> Float.Array.set x j (Float.Array.get y k)) s.fperm;
    x
  | Lu { ls = s; cols; pivots; llp; llx; ulp; ulx } ->
    let n = s.n and super = s.super and rp = s.rp in
    let y = Float.Array.init n (fun k -> Float.Array.get b s.fperm.(k)) and w = Float.Array.make n 0. in
    let t = Float.Array.make (max 1 s.widest) 0. in
    for g = 0 to Array.length super - 2 do
      let f0 = super.(g) and k = super.(g + 1) - super.(g) and r0 = rp.(g) and m = rp.(g + 1) - rp.(g) in
      let u = m - k in
      for j = 0 to k - 1 do
        let o = llp.(g) + (j * m) and z = Float.Array.get y pivots.(r0 + j) in
        Float.Array.set w (f0 + j) z;
        for q = j + 1 to k - 1 do
          let i = pivots.(r0 + q) in
          Float.Array.set y i (Float.Array.get y i -. (Float.Array.get llx (o + q) *. z))
        done
      done;
      if u * k >= least then begin
        Float.Array.fill t 0 u 0.;
        update ~pay:nothing ~rows:u ~cols:1 ~inner:k ~trans:false (vec t 0 u) (vec llx (llp.(g) + k) m) (vec w f0 k);
        for q = 0 to u - 1 do
          let i = pivots.(r0 + k + q) in
          Float.Array.set y i (Float.Array.get y i +. Float.Array.get t q)
        done
      end
      else
        for j = 0 to k - 1 do
          let o = llp.(g) + (j * m) and z = Float.Array.get w (f0 + j) in
          for q = k to m - 1 do
            let i = pivots.(r0 + q) in
            Float.Array.set y i (Float.Array.get y i -. (Float.Array.get llx (o + q) *. z))
          done
        done
    done;
    for g = Array.length super - 2 downto 0 do
      let f0 = super.(g) and k = super.(g + 1) - super.(g) and r0 = rp.(g) and m = rp.(g + 1) - rp.(g) in
      let u = m - k in
      for q = 0 to u - 1 do
        Float.Array.set t q (Float.Array.get w cols.(r0 + k + q))
      done;
      if u * k >= least then update ~pay:nothing ~rows:k ~cols:1 ~inner:u ~trans:false (vec w f0 k) (vec ulx ulp.(g) k) (vec t 0 u)
      else
        for q = 0 to u - 1 do
          let xc = Float.Array.get t q and o = ulp.(g) + (q * k) in
          for j = 0 to k - 1 do
            Float.Array.set w (f0 + j) (Float.Array.get w (f0 + j) -. (Float.Array.get ulx (o + j) *. xc))
          done
        done;
      for j = k - 1 downto 0 do
        let o = llp.(g) + (j * m) in
        let xj = Float.Array.get w (f0 + j) /. Float.Array.get llx (o + j) in
        Float.Array.set w (f0 + j) xj;
        for i = 0 to j - 1 do
          Float.Array.set w (f0 + i) (Float.Array.get w (f0 + i) -. (Float.Array.get llx (o + i) *. xj))
        done
      done
    done;
    let x = Float.Array.make n 0. in
    Array.iteri (fun k j -> Float.Array.set x j (Float.Array.get w k)) s.fperm;
    x

