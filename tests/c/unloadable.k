-- A library that is there but can't load says why, instead of being called absent.
use c

Print(c.Open(Args[1]) then MapErr(e -> Contains("kepler_nope", e.Message)))
