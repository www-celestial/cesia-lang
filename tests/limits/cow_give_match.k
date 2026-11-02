-- One arm gives the array back: it must stay owned.
defn passOn(e, xs)
  match e
    0 -> xs
    _ -> [e]
  end
end

defn run(n)
  x = Zeros(n)
  for i in 1:n
    x = passOn(0, x)
    x[i] = 1.0
  end
  x[n]
end
Print(run(100000))
