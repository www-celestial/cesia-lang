isRow() = Equal(Size([1, 2, 3]), [1, 3])
isColumn() = Equal(Size([1; 2; 3]), [3, 1])
isMatrix() = [1 2; 3 4][2, 1] == 3
isEmpty() = Len([]) == 0
isSpaceMinus() = Len([1 -2]) == 2 and Len([1 - 2]) == 1 and Len([1-2]) == 1
isCallInRow() = Len([Abs(1) Abs(2)]) == 2 and Len([Abs (1)]) == 2
isMultipleRows() = Equal(
  [1 2
   3 4], [1 2; 3 4])
isCommaNewline() = Equal([1,
  2], [1, 2])
isByColumns() = [1 2; 3 4][2] == 3
isWholeRow() = Equal([1 2; 3 4][2, :], [3, 4])
isWholeColumn() = Equal([1 2; 3 4][:, 2], [2; 4])
isSlice() = Equal([1, 2, 3, 4, 5][2:4], [2, 3, 4])
isEnd() = [1, 2, 3][end] == 3 and Equal([1, 2, 3][2:end], [2, 3])
isMaskAsIndex() = Equal([1, 2, 3][[true, false, true]], [1, 3])
isWholeFloatIndex() = [1, 2, 3][2.0] == 2
isZeros() = Equal(Zeros(2), [0.0, 0.0]) and Equal(Size(Zeros(2, 3)), [2, 3])
isFill() = Equal(Fill("a", 2), ["a", "a"])
isIntInF() = intInF()
isComp() = Equal([v * 2 for v in [1, -2, 3] if v > 0], [2, 6])
isCompLocal() = compLocal()
isForArray() = sumFor([1, 2, 3]) == 6
isForEmpty() = sumFor([]) == 0
isRangeArray() = Equal(1:3, [1, 2, 3])
isRangeEmpty() = Len(3:1) == 0
isIn() = 2 in [1, 2] and not (3 in 1:2)
isArrayInArray() = Len([[1, 2], 3]) == 2

defn intInF()
  x = Zeros(2)
  x[1] = 5
  IsFloat(x[1])
end
defn compLocal()
  v = 9
  r = [v for v in [1]]
  v == 9
end
defn sumFor(xs)
  s = 0
  for v in xs
    s += v
  end
  s
end
