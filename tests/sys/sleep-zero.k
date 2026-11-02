use sys

t = Spawn(() -> Print("fiber"))
sys.Sleep(0)
Print("main")
Wait(t)
