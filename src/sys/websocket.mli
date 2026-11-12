(** WebSocket, RFC 6455: the server side, which std/http hands its connections to, and the frames and the randomness of
    the client of std/websocket. *)
open Cesia

(** The contents of the [websocket] module that are written in OCaml: Accept, DefaultIdle and MaxFrame, and the small
    names that only std/websocket sees. *)
val natives : (string * Types.t) list
