(* A comment
   on several lines. *)
Print(1)
(* on one line *) Print(2)
Print(3 (* in the middle *) + 4)
(* An outer comment (* with an inner one *)
   is still open here. *)
Print(8)
(**)
(***)
(** a documentation comment **)
Print(9)
-- (* a line comment opens nothing
Print(10)
Print("(* a text *)")
(* a quote " in a comment *) Print(11)
x = 1 + (* over
two lines *) 2
Print(x)
