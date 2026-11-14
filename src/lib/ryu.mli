(** The text of a float, by Ryu's tables: what C's printf "%.15g", else "%.16g", else "%.17g" writes, the first that
    reads back to the same float, then "1.0" for a whole number, "1e15" and "1.5e-7" for an exponent, "nan", "inf",
    "-inf" and "-0.0". *)

(** [write b at x] writes the text of [x] in [b] from [at], at most 24 bytes, and returns where it ends. *)
val write : Bytes.t -> int -> float -> int
