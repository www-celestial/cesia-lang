-- A persistent queue open at both ends. Every operation is logarithmic, and a change gives a new queue.

-- A queue with nothing in it.
Empty() = {Items: Dict(), First: 1, Last: 0}
-- How many elements the queue holds.
--
--   Count(Of([1, 2])) --> 2
Count(q) = q.Last - q.First + 1
-- Is this queue empty?
--
--   IsEmpty(Empty()) --> true
IsEmpty(q) = Count(q) == 0

-- A queue with x added at the back.
--
--   Items(Push(2, Of([1]))) --> [1, 2]
defn Push(x, q)
  {Items: Put(q.Last + 1, x, q.Items), First: q.First, Last: q.Last + 1}
end

-- A queue with x added at the front.
--
--   Items(PushFront(0, Of([1]))) --> [0, 1]
defn PushFront(x, q)
  {Items: Put(q.First - 1, x, q.Items), First: q.First - 1, Last: q.Last}
end

-- The element at the front, or missing.
--
--   First(Of([1, 2])) --> 1
First(q) = Get(q.First, q.Items)
-- The element at the back, or missing.
--
--   Last(Of([1, 2])) --> 2
Last(q) = Get(q.Last, q.Items)

-- A queue without its front element.
--
--   Items(Pop(Of([1, 2]))) --> [2]
defn Pop(q)
  if IsEmpty(q) q else {Items: Drop(q.First, q.Items), First: q.First + 1, Last: q.Last} end
end

-- A queue without its back element.
--
--   Items(PopBack(Of([1, 2]))) --> [1]
defn PopBack(q)
  if IsEmpty(q) q else {Items: Drop(q.Last, q.Items), First: q.First, Last: q.Last - 1} end
end

-- The elements from front to back.
--
--   Items(Of([1, 2])) --> [1, 2]
Items(q) = Values(q.Items)
-- A queue holding the elements of an array, the first one at the front.
Of(xs) = Reduce((q, x) -> Push(x, q), Empty(), xs)
