add(a, b) = a + b
defn waitTwice()
  t = Spawn(() -> 1)
  Wait(t) == Wait(t)
end
defn copied()
  a = [1, 2]
  t = Spawn(() -> a[1])
  a[1] = 9
  Wait(t) == Ok(1)
end
isWaitValue() = Wait(Spawn(() -> add(1, 2))) == Ok(3)
isWaitTwice() = waitTwice()
isPanicIsErr() = IsErr(Wait(Spawn(() -> Panic("x"))))
isPanicMessage() = (Wait(Spawn(() -> Panic("x"))) then MapErr(it.Message)) == Err("x")
isTypePanic() = (Wait(Spawn(() -> 1 + "a")) then MapErr(it.Kind)) == Err("type")
isValueCopied() = copied()
isWaitNotATask() = IsErr(Wait(Spawn(() -> Wait(1))))
isSpawnInSpawn() = Wait(Spawn(() -> Wait(Spawn(() -> 1)))) == Ok(Ok(1))

half(x) = Ok(Div(x, 2))
countDown(n) = if n == 0 0 else 0 + countDown(n - 1) end
isPmap() = Equal([1, 2, 3] then Pmap(it * 2), [2, 4, 6])
isPmapEmpty() = Equal([] then Pmap(it * 2), [])
isPmapCollect() = Equal([2, 4] then Pmap(half) then Collect, Ok([1, 2]))
isPmapPanics() = IsErr(Wait(Spawn(() -> Pmap(x -> Panic("x"), [1]))))
isManyFibers() = Len(Pmap(it + 1, 1:10000)) == 10000
isDeepInFiber() = Wait(Spawn(() -> countDown(5000))) == Ok(0)
