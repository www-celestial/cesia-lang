type t = int

let make line col = (line lsl 12) lor (if col < 4095 then col else 4095)
let line p = p lsr 12
let col p = p land 4095

exception Load_error of { file : string; pos : t; kind : string; text : string; hint : string option }
