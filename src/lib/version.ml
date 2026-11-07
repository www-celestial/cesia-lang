(* The release job of the CI removes +dev, or makes it -nightly+SHORTSHA, before it builds. *)
let text = "cesia 1.0.0+dev"

(* What follows a + or a - says how it was built, not which version it is. *)
let bare v =
  let v = if String.starts_with ~prefix:"v" v then String.sub v 1 (String.length v - 1) else v in
  match String.index_opt v '+', String.index_opt v '-' with
  | Some i, Some j -> String.sub v 0 (min i j)
  | Some i, None | None, Some i -> String.sub v 0 i
  | None, None -> v

let number = bare (String.sub text 6 (String.length text - 6))
let dev = String.ends_with ~suffix:"+dev" text
let is_digit c = c >= '0' && c <= '9'
let is_part p = p <> "" && String.for_all is_digit p
let valid v = List.for_all is_part (String.split_on_char '.' (bare v))

let parts v =
  List.map
    (fun p -> if is_part p then Option.value ~default:max_int (int_of_string_opt p) else 0)
    (String.split_on_char '.' (bare v))

let compare a b =
  let first = function [] -> 0, [] | x :: rest -> x, rest in
  let rec go a b =
    if a = [] && b = [] then 0
    else
      let x, a = first a and y, b = first b in
      if x <> y then Int.compare x y else go a b
  in
  go (parts a) (parts b)

let at_least v = compare number v >= 0
