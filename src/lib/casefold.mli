(** Unicode's simple case folding, the statuses C and S of its CaseFolding.txt, which src/gen/gen_fold.ml writes into
    casefold.ml: each character to one character, the same for its capital and its small letter. *)

(** The runs of characters that move by the same distance, rising: four numbers each, its first character, its last, the
    step between two of them (1, or 2 where capitals and small letters alternate) and the distance each moves. *)
val runs : int array
