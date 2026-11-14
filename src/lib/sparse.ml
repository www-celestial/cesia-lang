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
