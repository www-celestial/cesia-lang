-- Bytes could spell any address, so a pointer can't come from a block before a library is open.
use c

defn message(f)
  match Wait(Spawn(f))
    Err(e) -> Print(e.Message)
    Ok(v) -> Print("no panic: $v")
  end
end

b = c.Alloc(8)
c.Set("i64", 0, 12345, b)
message(() -> c.Get("ptr", 0, b))
message(() -> c.Text(b))
message(() -> c.Text(missing))
message(() -> c.Set("ptr", 0, b, b))
c.Open("m", version = 6)
Print(IsMissing(c.Get("ptr", 0, b)))
