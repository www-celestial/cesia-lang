let count =
  lazy
    (match Option.bind (Sys.getenv_opt "CESIA_CORES") int_of_string_opt with
     | Some n when n >= 1 -> min n 64
     | _ -> max 1 (min 16 (Domain.recommended_domain_count () / 2)))

let cores () = Lazy.force count

(* The caller takes the last part. A domain that can't start only means that the caller does its part too. *)
let each n f =
  if n = 1 then f 0
  else if n > 1 then begin
    let start k =
      match Domain.spawn (fun () -> f k) with
      | d -> Some d
      | exception Failure _ ->
        f k;
        None
    in
    let started = List.init (n - 1) start in
    f (n - 1);
    List.iter (Option.iter Domain.join) started
  end

let ranges ?(grain = 1 lsl 17) n f =
  let parts = if n < 2 * grain then 1 else min (cores ()) (n / grain) in
  if parts <= 1 then f 0 n else each parts (fun k -> f (n * k / parts) (n * (k + 1) / parts))
