local function simulate(n, steps)
  local ps = {}
  for i = 1, n do ps[i] = {x = i * 1.0, y = 0.0, vx = 1.0, vy = i * 0.5} end
  local dt = 0.001
  for s = 1, steps do
    for i = 1, n do
      local p = ps[i]
      local vy = p.vy - 9.81 * dt
      ps[i] = {x = p.x + p.vx * dt, y = p.y + vy * dt, vx = p.vx, vy = vy}
    end
  end
  local e = 0.0
  for i = 1, n do local p = ps[i]; e = e + p.x + p.y end
  return e
end
print(string.format("%.6f", simulate(1000, 5000)))
