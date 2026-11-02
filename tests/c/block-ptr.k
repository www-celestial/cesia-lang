-- A block given to C is a pointer, and its address can be stored in another block.
use c

lib = Unwrap(c.Open(Args[1]))
echo = Unwrap(c.Fn("echo_ptr", ["ptr"], "ptr", lib))
b = c.Alloc(8)
holder = c.Alloc(8)
c.Set("ptr", 0, b, holder)
Print(echo(b) == echo(b), echo(b) == b, c.Get("ptr", 0, holder) == echo(b))
c.Set("ptr", 0, echo(b), holder)
Print(c.Get("ptr", 0, holder) == echo(b))
c.Set("ptr", 0, missing, holder)
Print(IsMissing(c.Get("ptr", 0, holder)))
