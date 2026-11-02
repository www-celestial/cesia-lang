defn spin(n)
  s = 0
  for i in 1:n
    s += 1
  end
  Print("spin")
end
a = Spawn(() -> spin(3000000))
b = Spawn(() -> Print("quick"))
Wait(a)
Wait(b)
