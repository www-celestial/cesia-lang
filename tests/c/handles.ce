-- A block and a task can have the same id without being equal.
use c

f() = 1
t = Spawn(f)
b = c.Alloc(8)
Wait(t)
Print(b == t, b == b, b == c.Alloc(8))
