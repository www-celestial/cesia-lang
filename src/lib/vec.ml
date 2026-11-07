(* The cells past [size] hold a value added before, never read: a new array is filled with the value it grows for. *)
type 'a t = { mutable items : 'a array; mutable size : int }

let create () = { items = [||]; size = 0 }
let length v = v.size
let get v i = if i >= v.size then invalid_arg "Vec.get" else v.items.(i)
let set v i x = if i >= v.size then invalid_arg "Vec.set" else v.items.(i) <- x
let get_last v = get v (v.size - 1)

let[@inline] add_last v x =
  if v.size = Array.length v.items then begin
    let bigger = Array.make (max 8 (2 * v.size)) x in
    Array.blit v.items 0 bigger 0 v.size;
    v.items <- bigger
  end;
  v.items.(v.size) <- x;
  v.size <- v.size + 1

let clear v = v.size <- 0
let to_array v = Array.sub v.items 0 v.size
let to_list v = Array.to_list (to_array v)
let iter f v = for i = 0 to v.size - 1 do f v.items.(i) done
