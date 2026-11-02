r = Wait(Spawn(() -> Panic("x")))
Print(r.Error.File, r.Error.Line)
