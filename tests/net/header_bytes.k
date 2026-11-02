-- Every byte of a header name against the list of RFC 9110, and a line end refused anywhere in the line.
use net

allowed = Bytes("!#$$%&'*+-.^_`|~abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
accepted(b) = net.IsHeader(1, "$(FromBytes([b])): value")

Print(Equal(Filter(accepted, [b for b in 0:255]), Sort(allowed)))
Print(net.IsHeader(1, "a: b"))
Print(net.IsHeader(0, ": b"))
Print(net.IsHeader(2, "a : b"))
Print(net.IsHeader(2, "a\nb: c"))
Print(net.IsHeader(1, "a: b\nc"))
Print(net.IsHeader(1, "a: b\rc"))
Print(net.IsHeader(1, "a: tab	space é"))
Print(Wait(Spawn(() -> net.IsHeader(9, "a"))) then MapErr(it.Kind))
