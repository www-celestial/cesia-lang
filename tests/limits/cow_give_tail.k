defn go(acc, i, n)
  if i > n
    acc
  else
    acc[i] = 1.0
    go(acc, i + 1, n)
  end
end

result = go(Zeros(100000), 1, 100000)
Print(result[100000])
