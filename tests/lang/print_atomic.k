a = Fill([], 10000)
defn lines()
  for i in 1:200
    Print("x", a)
  end
end
defn others()
  for i in 1:400000
    Print("B")
  end
end
t = Spawn(lines)
u = Spawn(others)
Wait(t)
Wait(u)
