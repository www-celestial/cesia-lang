open Cesia
open Types

external dlopen : string -> int = "cesia_dlopen"
external dlsym : int -> string -> int = "cesia_dlsym"
(* dgemm f d out x y: out = alpha x op(y) + beta out, on blocks of the three arrays; d holds rows, cols, inner, the
   leading dimensions of x, y and out, their offsets, 1 when op(y) is y', alpha and beta. [gemm] checks every block. *)
external dgemm : int -> int array -> floatarray -> floatarray -> floatarray -> unit = "cesia_dgemm" [@@noalloc]
external dgesv : int -> int -> int -> floatarray -> floatarray -> int = "cesia_dgesv" [@@noalloc]
external dgetrf : int -> int -> floatarray -> floatarray -> int = "cesia_dgetrf" [@@noalloc]
external qr_factors : int -> int -> int array -> floatarray -> floatarray -> int = "cesia_qr" [@@noalloc]
external dsyev : int -> int -> floatarray -> floatarray -> int = "cesia_dsyev" [@@noalloc]

(* [threads]: the threads OpenBLAS takes by itself, and its functions that read and set them; 0 for another library. *)
type library = {
  name : string;
  fast : bool;
  gemm : int;
  gesv : int;
  getrf : int;
  geqrf : int;
  orgqr : int;
  syev : int;
  threads : int;
  set_threads : int;
  mutable current : int;
}

(* A fast library first. LAPACK brings the BLAS it was linked with. *)
let candidates =
  [ "libopenblas.so.0"; "libopenblas.so"; "liblapack.so.3"; "liblapack.so"; "libopenblas.dylib";
    "/System/Library/Frameworks/Accelerate.framework/Accelerate"; "libopenblas.dll"; "liblapack.dll" ]

(* The reference BLAS does matmul on one core, which the kernels of OCaml beat on several. *)
let open_library ?(chosen = false) name =
  match dlopen name with
  | 0 -> None
  | handle ->
    let symbol s = dlsym handle s in
    let fast = chosen || symbol "openblas_get_config" <> 0 || String.ends_with ~suffix:"Accelerate" name in
    let get = symbol "openblas_get_num_threads" and set_threads = symbol "openblas_set_num_threads" in
    let threads = if get <> 0 && set_threads <> 0 then max 1 (C.call_ints get [||]) else 0 in
    let lib = { name; fast; gemm = symbol "dgemm_"; gesv = symbol "dgesv_"; getrf = symbol "dgetrf_"; geqrf = symbol "dgeqrf_";
                orgqr = symbol "dorgqr_"; syev = symbol "dsyev_"; threads; set_threads; current = threads } in
    if List.mem 0 [ lib.gemm; lib.gesv; lib.getrf; lib.geqrf; lib.orgqr; lib.syev ] then None else Some lib

let library =
  lazy
    (match Sys.getenv_opt "CESIA_BLAS" with
     | Some "none" -> None
     | Some name -> open_library ~chosen:true name
     | None -> List.find_map open_library (C.in_release candidates @ candidates))

(* Below this order, the code of Cesia is fast enough and gives the same bits on every machine. *)
let min_order = 32

(* The Fortran interface counts in 32 bits. *)
let max_order = 1 lsl 30

let fits n = n >= min_order && n <= max_order

(* OpenBLAS on at most [threads] threads, or on its own count for 0, for the calls that follow. *)
let use_threads lib threads =
  let want = if threads = 0 then lib.threads else min threads lib.threads in
  if lib.set_threads <> 0 && want <> lib.current then begin
    ignore (C.call_ints lib.set_threads [| want |]);
    lib.current <- want
  end

(* A block of rows x cols cells inside its array, its leading dimension within the 32 bits of Fortran. *)
let inside { Kernels.data; offset; ld } rows cols =
  offset >= 0 && ld >= max 1 rows && ld <= max_order
  && (rows = 0 || cols = 0 || offset + ((cols - 1) * ld) + rows <= Float.Array.length data)

let install () =
  Kernels.gemm :=
    fun ~rows ~cols ~inner ~trans ~sub ~threads ({ Kernels.data = od; offset = oo; ld = ol } as out)
      ({ Kernels.data = xd; offset = xo; ld = xl } as x) ({ Kernels.data = yd; offset = yo; ld = yl } as y) ->
      rows >= 0 && cols >= 0 && inner >= 0 && rows <= max_order && cols <= max_order && inner <= max_order
      && inside out rows cols && inside x rows inner
      && (if trans then inside y cols inner else inside y inner cols)
      &&
      match Lazy.force library with
      | Some lib when lib.fast ->
        use_threads lib threads;
        let d = [| rows; cols; inner; xl; yl; ol; xo; yo; oo; Bool.to_int trans; 1; 0 |] in
        if sub then (d.(10) <- -1; d.(11) <- 1);
        dgemm lib.gemm d od xd yd;
        true
      | _ -> false

(* A copy of a matrix of numbers with its shape, which LAPACK can overwrite. *)
let matrix ctx v =
  match v with
  | Array a when a.rows * a.cols > 0 && Array.length a.dims = 0 ->
    Runtime.reserve ctx (a.rows * a.cols);
    Option.map
      (fun d -> a.rows, a.cols, d)
      (match (Value.trim a).store with
       | F d -> Some (Float.Array.copy d)
       | _ ->
         let d = Float.Array.create (a.rows * a.cols) in
         let rec fill k =
           k >= a.rows * a.cols
           || (match Value.elt a k with
               | Int i -> Float.Array.set d k (float_of_int i); fill (k + 1)
               | Float x -> Float.Array.set d k x; fill (k + 1)
               | _ -> false)
         in
         if fill 0 then Some d else None)
  | _ -> None

let square ctx v =
  match matrix ctx v with
  | Some (n, m, d) when n = m && fits n -> Some (n, d)
  | _ -> None

(* The work of a factorisation grows with the cube of its order. *)
let pay ctx n = Runtime.pay ctx (n * n * n)

(* Calls [f] when the machine has a library and the arguments suit it. *)
let with_library f =
  match Lazy.force library with
  | None -> Missing
  | Some lib ->
    use_threads lib 0;
    f lib

let record (_ : world) names values = Trie.record (Trie.names names) values

(* Solve(a, b), where b has one column or more: its x, false if a is singular. *)
let solve ctx (a : t array) =
  with_library (fun lib ->
      match square ctx a.(0), matrix ctx a.(1) with
      | Some (n, m), Some (rows, cols, b) when rows = n ->
        pay ctx n;
        (match dgesv lib.gesv n cols m b with
         | 0 -> Arrays.of_float n cols b
         | info when info > 0 -> False
         | _ -> Missing)
      | _ -> Missing)

let det ctx (a : t array) =
  with_library (fun lib ->
      match square ctx a.(0) with
      | None -> Missing
      | Some (n, m) ->
        pay ctx n;
        let sign = Float.Array.make 1 1. in
        (match dgetrf lib.getrf n m sign with
         | info when info < 0 -> Missing
         | info when info > 0 -> Float 0.
         | _ ->
           let acc = ref (Float.Array.get sign 0) in
           for k = 0 to n - 1 do acc := !acc *. Float.Array.get m ((k * n) + k) done;
           Float !acc))

(* The diagonal of R stays positive, as in the code of Cesia. *)
let qr ctx (a : t array) =
  with_library (fun lib ->
      match matrix ctx a.(0) with
      | Some (rows, cols, q) when rows >= cols && fits cols && rows <= max_order ->
        pay ctx cols;
        let r = Runtime.alloc_float ctx (cols * cols) 0. in
        (match qr_factors lib.geqrf lib.orgqr [| rows; cols |] q r with
         | 0 ->
           for j = 0 to cols - 1 do
             if Float.Array.get r ((j * cols) + j) < 0. then begin
               for k = j to cols - 1 do
                 Float.Array.set r ((k * cols) + j) (-.Float.Array.get r ((k * cols) + j))
               done;
               for i = 0 to rows - 1 do
                 Float.Array.set q ((j * rows) + i) (-.Float.Array.get q ((j * rows) + i))
               done
             end
           done;
           record ctx.w [| "Q"; "R" |] [| Arrays.of_float rows cols q; Arrays.of_float cols cols r |]
         | _ -> Missing)
      | _ -> Missing)

let eigen ctx (a : t array) =
  with_library (fun lib ->
      match square ctx a.(0) with
      | None -> Missing
      | Some (n, m) ->
        pay ctx n;
        let w = Runtime.alloc_float ctx n 0. in
        (match dsyev lib.syev n m w with
         | 0 -> record ctx.w [| "Values"; "Vectors" |] [| Arrays.of_float 1 n w; Arrays.of_float n n m |]
         | _ -> Missing))

let natives =
  [ "Name", Native.nat "Name" 0 0 (fun _ _ ->
        match Lazy.force library with None -> Missing | Some lib -> Text lib.name);
    "Solve", Native.nat "Solve" 2 2 solve;
    "Det", Native.nat "Det" 1 1 det;
    "Qr", Native.nat "Qr" 1 1 qr;
    "Eigen", Native.nat "Eigen" 1 1 eigen ]
