addTwo(a, b) = a + b
both(a, b) = [a, b]
apply(f, x) = f(x)
ordered(by = 0) = by({V: 7})

isLastPositional() = (10 then addTwo(1)) == 11
isValueAlone() = (4 then Sqrt) == 2.0
isItPlaced() = Equal(1 then both(it, 2), [1, 2])
isLastKeepsOrder() = Equal(1 then both(2), [2, 1])
isExpressionIt() = (2 then it * 3) == 6
isAnonymousFunction() = (2 then (x -> x + 1)) == 3
isArgumentIt() = apply(it + 1, 1) == 2
isItAloneInCall() = apply(addTwo(it, 2), 1) == 3
isNamed() = ordered(by = it.V) == 7
isNestedFunction() = apply(x -> (y -> y)(x), 1) == 1
isLambdaPrecedence() = (x -> x then Abs)(-1) == 1
isMultiline() = multi() == 6

defn multi()
  [1, 2, 3]
    then Map(it * 2)
    then Sum(it) / 2
end
