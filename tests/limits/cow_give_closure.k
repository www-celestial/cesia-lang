defn run(n, f)
  x = Zeros(n)
  for i in 1:n
    x = f(x, i)
  end
  x[n]
end

defn writeOne(xs, i)
  xs[i] = 1.0
  xs
end
Print(run(100000, writeOne))
