-- Calls lend values to functions that only read them, and hand over variables that end with the call. None of it may
-- show: what a function does to its arguments stays invisible to the caller.

same(x) = x
head(s) = s.V
box(x) = {V: x}
later(x) = () -> x[1]
first(x, y) = x[1]
twice(x) = same(same(x))

defn touch(x)
  x[1] = 9
  x
end

defn touch4(x, p, q, r)
  x[1] = 9
  x
end

defn touchDefault(x, y = 1)
  x[1] = 9
  x
end

defn setX(r)
  r.X = 2
  r
end

-- Sixty-four parameters: past the 62 bits of the mask.
defn lastWritten(p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16, p17, p18, p19, p20, p21, p22, p23, p24, p25, p26, p27, p28, p29, p30, p31, p32, p33, p34, p35, p36, p37, p38, p39, p40, p41, p42, p43, p44, p45, p46, p47, p48, p49, p50, p51, p52, p53, p54, p55, p56, p57, p58, p59, p60, p61, p62, p63, p64)
  p64[1] = 9
  p64
end

-- A default value can write to the parameter before it.
defn writtenByDefault(x, y = if true
  x[1] = 9
  0
else
  0
end)
  x[1]
end

defn alias(x)
  y = x
  y[1] = 9
  x
end

defn soon(x)
  return x
  0
end

defn replaced(x)
  x = touch(x)
  x
end

-- Never returned nor written here: only reassigned.
defn replacedInside(x)
  x = touch(x)
  x[1]
end

defn touch2(x, p)
  x[1] = 9
  x
end

defn touch3(x, p, q)
  x[1] = 9
  x
end

pick(c, x, y) = if c x else y end

defn matched(e, x)
  match e
    0 -> x
    _ -> [e]
  end
end

defn clobber(x, y)
  x[1] = 9
  y[1]
end

defn merge(x, y)
  x[1] = 9
  x[2] = y[1]
  x
end

-- The array read at position 1 is written once it has moved to position 2.
defn spin(a, b, n)
  if n == 0
    0
  else
    b[1] = 9
    spin(b, a, n - 1)
  end
end

defn walk(x, i)
  if i > 2
    x
  else
    x[i] = 9
    walk(x, i + 1)
  end
end

defn isReturnedThenWritten()
  a = [1, 2]
  b = same(a)
  b[1] = 9
  a[1] == 1 and b[1] == 9
end

defn isReturnedThenCallerWrites()
  a = [1, 2]
  b = same(a)
  a[1] = 9
  b[1] == 1
end

defn isReturnedByTwoCalls()
  a = [1, 2]
  b = twice(a)
  b[1] = 9
  a[1] == 1
end

defn isReturnedByReturn()
  a = [1, 2]
  b = soon(a)
  b[1] = 9
  a[1] == 1
end

defn isReturnedByIf()
  a = [1, 2]
  b = pick(true, a, [3])
  b[1] = 9
  a[1] == 1
end

defn isReturnedByMatch()
  a = [1, 2]
  b = matched(0, a)
  b[1] = 9
  a[1] == 1
end

defn isPartReturned()
  s = {V: [1, 2]}
  v = head(s)
  v[1] = 9
  s.V[1] == 1
end

defn isStoredInAStruct()
  a = [1, 2]
  s = box(a)
  a[1] = 9
  s.V[1] == 1
end

defn isCaptured()
  a = [1, 2]
  g = later(a)
  a[1] = 9
  g() == 1
end

defn isWrittenByTheFunction()
  a = [1, 2]
  b = touch(a)
  a[1] == 1 and b[1] == 9
end

defn isWrittenThroughAnAlias()
  a = [1, 2]
  b = alias(a)
  a[1] == 1 and b[1] == 1
end

defn isReassignedByTheFunction()
  a = [1, 2]
  b = replaced(a)
  a[1] == 1 and b[1] == 9
end

defn isSameArrayTwice()
  a = [1, 2]
  clobber(a, a) == 1 and a[1] == 1
end

defn isReplacedWithItselfTwice()
  a = [1, 2]
  a = merge(a, a)
  a[1] == 9 and a[2] == 1
end

defn isReplacedWithItselfInsideAnIf()
  a = [1, 2]
  a = merge(a, if true a else [5] end)
  a[1] == 9 and a[2] == 1
end

defn isReplacedWithAPart()
  a = [1, 2]
  a = merge(a, [a[1] + 1])
  a[1] == 9 and a[2] == 2
end

defn isReplacedWhileAnAliasLives()
  a = [1, 2]
  b = a
  a = touch(a)
  a[1] == 9 and b[1] == 1
end

defn isReplacedDuringATraversal()
  a = [1, 2]
  seen = []
  for v in a
    a = touch(a)
    seen = Concat(seen, [v])
  end
  Equal(seen, [1, 2]) and a[1] == 9
end

defn isReplacedInAStruct()
  s = {X: 1}
  t = s
  s = setX(s)
  s.X == 2 and t.X == 1
end

defn isRotatedByTailRecursion()
  a = [1, 2]
  b = [3, 4]
  spin(a, b, 2)
  a[1] == 1 and b[1] == 3
end

defn isKeptByTailRecursion()
  a = [1, 2]
  b = walk(a, 1)
  a[1] == 1 and b[2] == 9
end

defn isWrittenInALaterArgument()
  a = [1, 2]
  r = first(a, if true
    a[1] = 9
    0
  else
    0
  end)
  r == 1 and a[1] == 9
end

defn isWrittenInALaterArgumentByClosure()
  a = [1, 2]
  f = (x, y) -> x[1]
  r = f(a, if true
    a[1] = 9
    0
  else
    0
  end)
  r == 1 and a[1] == 9
end

defn isNamedInAnotherOrder()
  a = [1, 2]
  b = [3, 4]
  r = clobber(y = a, x = b)
  r == 1 and a[1] == 1 and b[1] == 3
end

defn isWrittenByAClosure()
  a = [1, 2]
  f = x -> touch(x)
  b = f(a)
  a[1] == 1 and b[1] == 9
end

defn isWrittenByAClosureOfFour()
  a = [1, 2]
  f = touch4
  b = f(a, 1, 2, 3)
  a[1] == 1 and b[1] == 9
end

defn isWrittenByAClosureWithADefault()
  a = [1, 2]
  f = touchDefault
  b = f(a)
  a[1] == 1 and b[1] == 9
end

defn isReadInAFiber()
  a = [1, 2]
  t = Spawn(() -> same(a))
  a[1] = 9
  b = Unwrap(Wait(t))
  b[1] == 1 and a[1] == 9
end

defn isKeptByReduce()
  start = Zeros(1, 3)
  r = Reduce((acc, i) -> touch(acc), start, 1:3)
  start[1] == 0.0 and r[1] == 9.0
end

defn isStructWrittenByTheFunction()
  s = {X: 1}
  t = setX(s)
  s.X == 1 and t.X == 2
end

defn isPastTheMask()
  a = [1, 2]
  b = lastWritten(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, a)
  a[1] == 1 and b[1] == 9
end

defn isNamedOnAClosure()
  a = [1, 2]
  b = [3, 4]
  f = clobber
  r = f(y = a, x = b)
  r == 1 and a[1] == 1 and b[1] == 3
end

defn isWrittenByADefault()
  a = [1, 2]
  writtenByDefault(a) == 9 and a[1] == 1
end

defn isReassignedInside()
  a = [1, 2]
  replacedInside(a) == 9 and a[1] == 1
end

defn isWrittenThroughAVariableOfOne()
  a = [1, 2]
  f = touch
  b = f(a)
  a[1] == 1 and b[1] == 9
end

defn isWrittenThroughAVariableOfTwo()
  a = [1, 2]
  f = touch2
  b = f(a, 1)
  a[1] == 1 and b[1] == 9
end

defn isWrittenThroughAVariableOfThree()
  a = [1, 2]
  f = touch3
  b = f(a, 1, 2)
  a[1] == 1 and b[1] == 9
end
