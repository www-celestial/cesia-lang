local function maps(n)
  local m = {}
  for k = 1, n do m["key" .. k] = k end
  local total = 0
  for k = 1, n do total = total + m["key" .. k] end
  return total
end
print(maps(500000))
