reader(xs, i) = xs[i] + 1.0

defn run(n)
  s = {Cells: Zeros(n)}
  for i in 1:n
    s.Cells[i] = reader(s.Cells, i)
  end
  s.Cells[n]
end
Print(run(100000))
