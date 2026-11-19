(* The cells past [size] hold a value added before, never read: a new array is the old one twice. Made of the value it
   grows for, young, an array past 256 cells would first empty the whole young heap (OCaml's caml_make_vect), with every
   tree and closure a load had just made: the sites of the code a first plot.Svg compiles passed 512, 1,024, 2,048 and
   4,096 that way, four collections that moved 175K words to the major heap and a major cycle, 2.2 ms of its 6.9. *)
type 'a t = { mutable items : 'a array; mutable size : int }

let create () = { items = [||]; size = 0 }
let length v = v.size
let get v i = if i >= v.size then invalid_arg "Vec.get" else v.items.(i)
let set v i x = if i >= v.size then invalid_arg "Vec.set" else v.items.(i) <- x
let get_last v = get v (v.size - 1)

let[@inline] add_last v x =
  if v.size = Array.length v.items then
    v.items <- (if v.size = 0 then Array.make 8 x else Array.append v.items v.items);
  v.items.(v.size) <- x;
  v.size <- v.size + 1

let[@inline] push v x = add_last v x; v.size - 1

let clear v = v.size <- 0
let to_array v = Array.sub v.items 0 v.size
let to_list v = Array.to_list (to_array v)
let iter f v = for i = 0 to v.size - 1 do f v.items.(i) done
