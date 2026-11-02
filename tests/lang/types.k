defn floatTimes(x)
  y = 1.5
  y * x
end
isFMissing() = IsMissing(floatTimes(missing))
isFArray() = Equal(floatTimes([2.0, 4.0]), [3.0, 6.0])
isFInt() = floatTimes(2) == 3.0

defn mixed(c)
  x = 1
  if c
    x = 1.5
  end
  x
end
isJoin() = IsInt(mixed(false)) and IsFloat(mixed(true))

defn faBecomesA()
  x = Zeros(2)
  x[1] = "a"
  x[1]
end
isFaToA() = faBecomesA() == "a"

defn noAssignment(c)
  if c
    v = 1
  end
  v
end
isDefined() = noAssignment(true) == 1

intOrFloat(x) = x + 1
isTwoVersions() = intOrFloat(1) == 2 and intOrFloat(1.5) == 2.5

fib(n) = if n < 2 n else fib(n - 1) + fib(n - 2) end
isTypedRecursion() = fib(20) == 6765

even(n) = if n == 0 true else odd(n - 1) end
odd(n) = if n == 0 false else even(n - 1) end
isMutual() = even(10)

defn midReturn(x)
  if x > 0
    return 1.5
  end
  "neg"
end
isReturnA() = midReturn(1) == 1.5 and midReturn(-1) == "neg"

defn loopReturns()
  for i in 1:10
    if i == 3
      return i
    end
  end
  0
end
isReturnInLoop() = loopReturns() == 3
isBoolArith() = 0.05 * (1 > 0) == 0.05

defn constantFloats(y)
  x = 0.5
  x = 1.5 * 2.0
  x = x + (1.5 + 2.5)
  z = y
  z = 3.0 - 1.0
  w = y
  w = 1.0 / 2.0
  x + z + w
end
isConstantFloats() = constantFloats(0.5) == 9.5
