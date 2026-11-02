-- Runs forever: tools/reload_test.sh edits this file while it runs.
use lib

Print("start")

struct Point { X }

value() = 1
following() = value() + 1
point() = Point(1).X
readKept(xs) = xs[1]
(p Point) Value() = 1
Point.Made() = Point(1)
method() = Point.Made().Value()
held = Point(1)
old() = held.Value()

defn report(label, before, after)
  if not Equal(before, after)
    Print("$label $after")
  end
  after
end

attempt(f) = match Wait(Spawn(f))
  Ok(v) -> v
  Err(e) -> e.Kind
end

defn mainLoop()
  a = value()
  Print("value $a")
  b = 0
  c = 0
  d = 0
  e = 0
  f = 0
  g = 0
  h = 0
  i = 0
  x = [1, 2]
  while true
    a = report("value", a, value())
    b = report("following", b, attempt(following))
    c = report("direct", c, attempt(() -> value() + 1))
    d = report("lib", d, lib.Constant())
    e = report("point", e, point())
    f = report("kept", f, readKept(x))
    g = report("owner", g, x[1])
    h = report("method", h, attempt(method))
    i = report("old", i, attempt(old))
  end
end

defn watcher(seen)
  v = value()
  if not Equal(v, seen)
    Print("fiber $v")
  end
  watcher(v)
end

background = Spawn(() -> watcher(0))
mainLoop()
