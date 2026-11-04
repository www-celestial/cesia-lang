defn fails(f, kind)
  (Wait(Spawn(f)) then MapErr(it.Kind)) == Err(kind)
end
isPush() = Equal(Append(3, [1, 2]), [1, 2, 3]) and Equal(Append("a", []), ["a"])
isConcat() = Equal(Concat([1], [2, 3]), [1, 2, 3]) and Equal(Concat([], []), [])
isReverse() = Equal(Reverse([1, 2, 3]), [3, 2, 1])
isTake() = Equal(Take(2, [1, 2, 3]), [1, 2]) and Equal(Take(9, [1]), [1]) and Equal(Take(0, [1]), [])
isSkip() = Equal(Skip(1, [1, 2, 3]), [2, 3]) and Equal(Skip(9, [1]), [])
isIndexOf() = IndexOf(2, [1, 2]) == 2 and IsMissing(IndexOf(9, [1]))
isSort() = Equal(Sort([3, 1.5, 2]), [1.5, 2, 3]) and Equal(Sort(["b", "a"]), ["a", "b"])
isSortKeepsTheOriginal() = Equal(kept(), [2, 1])
isOrder() = Equal(Order([30, 10, 20]), [2, 3, 1])
isOrderStable() = Equal(Order([1, 1, 0]), [3, 1, 2])
isSortBy() = Equal(SortBy(it.Age, [{Age: 3}, {Age: 1}]), [{Age: 1}, {Age: 3}])
isSortMixed() = fails(() -> Sort([1, "a"]), "type")
isUnique() = Equal(Unique([1, 2, 1, "a", "a", 1.0]), [1, 2, "a"])
isUniqueAny() = Equal(Unique([[1], [1], {A: 1}, {A: 1}]), [[1], {A: 1}])
isFlatten() = Equal(Flatten([[1, 2], [3], 4]), [1, 2, 3, 4])
isZip() = Equal(Zip([1, 2, 3], ["a", "b"]), [[1, "a"], [2, "b"]])
isCount() = Count(it > 1, [1, 2, 3]) == 2
isFlatMap() = Equal(FlatMap(x -> [x, x], [1, 2]), [1, 1, 2, 2])
isMapValues() = Equal(MapValues(it * 2, {"a": 1}), {"a": 2})
isUpper() = Upper("aB-é") == "AB-é"
isEndsWith() = ("hello" then EndsWith("llo")) and not ("lo" then EndsWith("hello"))
isFind() = Find("l", "été hello") == 7 and IsMissing(Find("z", "a")) and Find("", "a") == 1
isRepeat() = Repeat(3, "ab") == "ababab" and Repeat(0, "a") == ""
isChars() = Equal(Chars("aé"), ["a", "é"])
isCode() = Code("é") == 233 and Code("a") == 97
isLines() = Equal(Lines("a\nb\r\nc\n"), ["a", "b", "c"]) and Equal(Lines(""), [])
isPadLeft() = PadLeft(3, "0", "7") == "007" and PadLeft(1, "0", "12") == "12"
isPadRight() = PadRight(3, ".", "é") == "é.."
isBytes() = Equal(Bytes("é"), [195, 169]) and FromBytes([195, 169]) == "é"
isByte() = Byte(1, "a") == 97 and ByteLength("é") == 2
isByteSlice() = ByteSlice(2, 3, "abcd") == "bc"
isByteFind() = ByteFind("c", 1, "abcabc") == 3 and ByteFind("c", 4, "abcabc") == 6 and IsMissing(ByteFind("z", 1, "a"))
isRepeatTooBig() = fails(() -> Repeat(-1, "a"), "type")

defn kept()
  xs = [2, 1]
  Sort(xs)
  xs
end
isBits() = BitAnd(12, 10) == 8 and BitOr(12, 10) == 14 and BitXor(12, 10) == 6 and BitNot(0) == -1
isShift() = BitShift(1, 4) == 16 and BitShift(16, -4) == 1 and BitShift(1, 70) == 0 and BitShift(-1, -1) > 0
isXorBytes() = XorBytes("a", XorBytes("a", "hello")) == "hello" and Byte(1, XorBytes("ab", "a")) == 0
isRepeatEmpty() = Repeat(1000000000000, "") == ""
isPadEmptyFiller() = PadLeft(5, "", "a") == "a"
