-- Sets of numbers and texts: the keys of a dictionary, in order.

-- A set with nothing in it.
Empty() = Dict()
-- A set of the elements of an array.
--
--   Count(Of([1, 2, 1])) --> 2
Of(xs) = Reduce((s, x) -> Put(x, true, s), Dict(), xs)
-- A set with x added.
--
--   Member(1, Add(1, Empty())) --> true
Add(x, s) = Put(x, true, s)
-- A set without x.
--
--   Count(Remove(1, Of([1, 2]))) --> 1
Remove(x, s) = Drop(x, s)
-- Is x in the set?
--
--   Member(1, Of([1])) --> true
Member(x, s) = Has(x, s)
-- The elements of the set, in order.
--
--   Items(Of([2, 1])) --> [1, 2]
Items(s) = Keys(s)
-- How many elements the set holds.
--
--   Count(Of([1, 2])) --> 2
Count(s) = Len(s)
-- The elements of either set.
--
--   Items(Union(Of([1]), Of([2]))) --> [1, 2]
Union(a, b) = Reduce((s, x) -> Put(x, true, s), a, Keys(b))
-- The elements of both sets.
--
--   Items(Intersection(Of([1, 2]), Of([2, 3]))) --> [2]
Intersection(a, b) = Of([x for x in Keys(a) if Has(x, b)])
-- The elements of the first set that aren't in the second.
--
--   Items(Difference(Of([1, 2]), Of([2]))) --> [1]
Difference(a, b) = Of([x for x in Keys(a) if not Has(x, b)])
-- Are all the elements of the first set in the second?
--
--   Subset(Of([1]), Of([1, 2])) --> true
Subset(a, b) = All([Has(x, b) for x in Keys(a)])
