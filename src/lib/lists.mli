(** Natives of std/list, std/text and std/math for lists, texts and bits: no parsing cost, unlike a package in Cesia. *)
open Types

(** Each package with its natives: [descending] stays inside std/list. *)
val packages : (string * (string * t) list) list
