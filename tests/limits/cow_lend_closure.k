defn run(n, f)
  x = Zeros(n)
  for i in 1:n
    x[i] = f(x, i)
  end
  x[n]
end
Print(run(100000, (xs, i) -> xs[i] + 1.0))
