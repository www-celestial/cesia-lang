local function dyn(n)
  local ops = {function(a, b) return a + b end, function(a, b) return a * 0.5 + b end}
  local xs = {1, 2.5, 3, 4.5}
  local total = 0.0
  for i = 1, n do
    local f = ops[i % 2 + 1]
    local x = xs[i % 4 + 1]
    total = f(total, x)
    if total > 1000000.0 then
      total = total / 2
    end
  end
  return total
end
print(string.format("%.6f", dyn(10000000)))
