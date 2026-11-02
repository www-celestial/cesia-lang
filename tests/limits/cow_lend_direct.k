reader(xs, i) = xs[i] + 1.0

defn run(n)
  x = Zeros(n)
  for i in 1:n
    x[i] = reader(x, i)
  end
  x[n]
end
Print(run(100000))
