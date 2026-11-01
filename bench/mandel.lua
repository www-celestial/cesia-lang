local function mandel(w, h, maxit)
  local total = 0
  for py = 0, h - 1 do
    local y0 = 2.0 * py / h - 1.0
    for px = 0, w - 1 do
      local x0 = 3.0 * px / w - 2.0
      local x, y, x2, y2 = 0.0, 0.0, 0.0, 0.0
      local it = 0
      while x2 + y2 < 4.0 and it < maxit do
        y = 2.0 * x * y + y0
        x = x2 - y2 + x0
        x2 = x * x
        y2 = y * y
        it = it + 1
      end
      total = total + it
    end
  end
  return total
end
print(mandel(600, 400, 200))
