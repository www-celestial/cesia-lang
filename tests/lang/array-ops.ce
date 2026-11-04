isMulElements() = Equal([1, 2] * [3, 4], [3, 8])
isScalar() = Equal([1.0, 2.0] * 2, [2.0, 4.0]) and Equal(2 + [1, 2], [3, 4])
isMask() = Equal([1, 2, 3] > 1, [false, true, true])
isCountMask() = Sum([1, 2, 3] > 1) == 2
isMaskMissing() = Any([missing, true]) and not All([missing, true])
isMatmul() = Equal(Matmul([1 2; 3 4], [1; 1]), [3.0; 7.0])
isTranspose() = Equal(Transpose([1, 2]), [1; 2])
isReshape() = Equal(Reshape([1, 2, 3, 4], 2, 2), [1 3; 2 4])
isSqrtArray() = Equal(Sqrt([4.0, 9.0]), [2.0, 3.0])
isMinOne() = Min([3, 1, 2]) == 1
isMaxTwo() = Equal(Max([1, 5], [4, 2]), [4, 5])
isSumInt() = IsInt(Sum([1, 2]))
isMean() = Mean([1, 2]) == 1.5
isSumMissing() = IsMissing(Sum([1, missing]))
