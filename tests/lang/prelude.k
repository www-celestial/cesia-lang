isMap() = Equal(Map(it * 2, [1, 2]), [2, 4])
isMapColumn() = Equal(Map(it * 2, [1; 2]), [2; 4])
isMapNative() = Equal(Map(Sqrt, [4.0]), [2.0])
isFilter() = Equal(Filter(it > 1, [1, 2, 3]), [2, 3])
isReduce() = Reduce((a, x) -> a + x, 0, [1, 2, 3]) == 6
isScan() = Equal(Scan((a, x) -> a + x, 0, [1, 2, 3]), [1, 3, 6])
isRangeStep() = Equal(Range(1, 10, step = 3), [1, 4, 7, 10])
isRangeFloat() = Equal(Range(0, 1, step = 0.25), [0.0, 0.25, 0.5, 0.75, 1.0])
isRangeRounding() = Len(Range(0, 8, step = 0.001)) == 8001
isRangeDescending() = Equal(Range(3, 1, step = -1), [3, 2, 1])
isGroup() = Equal(Group(Mod(it, 2), [1, 2, 3, 4]), [{Key: 1, Values: [1, 3]}, {Key: 0, Values: [2, 4]}])
isGroupSummary() = Equal(Group(Mod(it, 2), [1, 2, 3, 4], summary = g -> {Total: Sum(g)}),
                          [{Key: 1, Total: 4}, {Key: 0, Total: 6}])
isGroupValue() = Equal(Group(Mod(it, 2), [1, 2], summary = Sum), [{Key: 1, Value: 1}, {Key: 0, Value: 2}])
isTop() = Equal(Top(2, [5, 1, 9, 3]), [9, 5])
isTopBy() = Equal(Top(1, [{V: 1}, {V: 7}], by = it.V), [{V: 7}])
isTopStable() = Equal(Top(2, [{V: 1, N: 1}, {V: 1, N: 2}], by = it.V), [{V: 1, N: 1}, {V: 1, N: 2}])
isTopNan() = Len(Top(2, [Nan, 1.0, 2.0])) == 2
