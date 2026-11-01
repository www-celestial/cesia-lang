local function matmul(n)
  local a, b, c = {}, {}, {}
  for i = 1, n * n do a[i] = 0.0; b[i] = 0.0; c[i] = 0.0 end
  for i = 0, n - 1 do
    for j = 0, n - 1 do
      a[i * n + j + 1] = (i + j) * 0.5
      b[i * n + j + 1] = (i - j) * 0.25
    end
  end
  for i = 0, n - 1 do
    for j = 0, n - 1 do
      local s = 0.0
      for k = 0, n - 1 do
        s = s + a[i * n + k + 1] * b[k * n + j + 1]
      end
      c[i * n + j + 1] = s
    end
  end
  return c[n + 2]
end
print(string.format("%.6f", matmul(300)))
