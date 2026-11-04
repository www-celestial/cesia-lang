defn mandel(w, h, maxit)
  total = 0
  for py in 0:h - 1
    y0 = 2.0 * py / h - 1.0
    for px in 0:w - 1
      x0 = 3.0 * px / w - 2.0
      x = 0.0
      y = 0.0
      iter = 0
      x2 = 0.0
      y2 = 0.0
      while x2 + y2 < 4.0 and iter < maxit
        y = 2.0 * x * y + y0
        x = x2 - y2 + x0
        x2 = x * x
        y2 = y * y
        iter = iter + 1
      end
      total = total + iter
    end
  end
  total
end
Print(mandel(600, 400, 200))
