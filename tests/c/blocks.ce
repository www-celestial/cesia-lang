-- Blocks need no permission: they are checked, and counted against the memory limit.
use c

b = c.Alloc(64)
Print(c.Get("i64", 0, b), c.Get("u8", 63, b), c.Get("f64", 56, b), c.Get("bool", 0, b))

defn roundTrip(type, value, last)
  c.Set(type, 0, value, b)
  c.Set(type, last, value, b)
  [c.Get(type, 0, b), c.Get(type, last, b)]
end

Print(roundTrip("i8", -5, 63))
Print(roundTrip("u8", 250, 63))
Print(roundTrip("i16", -300, 62))
Print(roundTrip("u16", 65000, 62))
Print(roundTrip("i32", -70000, 60))
Print(roundTrip("u32", 4000000000, 60))
Print(roundTrip("i64", -5000000000, 56))
Print(roundTrip("u64", 5000000000, 56))
Print(roundTrip("f32", 1.5, 60))
Print(roundTrip("f64", 0.1, 56))
Print(roundTrip("bool", true, 63))
Print(c.Free(b))
