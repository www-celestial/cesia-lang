-- A persistent leftist heap: the smallest key comes out first.

-- A heap with nothing in it.
Empty() = missing
-- Is this heap empty?
--
--   IsEmpty(Empty()) --> true
IsEmpty(h) = IsMissing(h)
rank(h) = if IsMissing(h) 0 else h.Rank end

defn node(key, value, a, b)
  if rank(a) >= rank(b)
    {Key: key, Value: value, Left: a, Right: b, Rank: rank(b) + 1}
  else
    {Key: key, Value: value, Left: b, Right: a, Rank: rank(a) + 1}
  end
end

-- One heap from two.
defn Merge(a, b)
  if IsMissing(a)
    b
  else if IsMissing(b)
    a
  else if a.Key <= b.Key
    node(a.Key, a.Value, a.Left, Merge(a.Right, b))
  else
    node(b.Key, b.Value, b.Left, Merge(a, b.Right))
  end
end

-- A heap with a value added under a key; the smallest key comes out first.
--
--   Peek(Insert(1, "a", Empty())).Value --> "a"
Insert(key, value, h) = Merge(node(key, value, missing, missing), h)
-- The smallest key and its value, as a struct with key and value. The heap must not be empty.
--
--   Peek(Insert(2, "b", Insert(1, "a", Empty()))).Key --> 1
Peek(h) = {Key: h.Key, Value: h.Value}
-- The heap without its smallest key. The heap must not be empty.
--
--   Peek(Pop(Insert(2, "b", Insert(1, "a", Empty())))).Key --> 2
Pop(h) = Merge(h.Left, h.Right)

-- All the entries as structs with key and value, smallest key first.
--
--   Len(Items(Insert(1, "a", Empty()))) --> 1
defn Items(h)
  out = Dict()
  while not IsMissing(h)
    out[Len(out) + 1] = Peek(h)
    h = Pop(h)
  end
  Values(out)
end
