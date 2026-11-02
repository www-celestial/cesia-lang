s = Repeat(1000000, "a")
p = "$(Repeat(500000, "a"))b"
Print(Find(p, s), Contains(p, s), ByteFind(p, 1, s))
