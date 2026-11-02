-- A tree walk that passes the sheet down, as a formula does.
defn walk(depth, xs, i)
  if depth == 0
    xs[i]
  else
    walk(depth - 1, xs, i) + walk(depth - 1, xs, i)
  end
end

defn run(n)
  x = Fill(0.75, n)
  for i in 1:n
    x[i] = walk(2, x, i)
  end
  x[n]
end
Print(run(100000))
