t = Spawn(() -> Panic("boom"))
Print(IsErr(Wait(t)))
