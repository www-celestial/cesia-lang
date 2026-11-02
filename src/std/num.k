-- Numerical computing, in the spirit of numpy. An array is a list or a matrix of floats, and the operators of the
-- language already work element by element: a + b, a * 2.0, a > 0.0, Matmul(a, b), Transpose(a), Sum(a), Mean(a).
use lapack

-- The library that does the large computations, or missing if the code of Kepler does them all.
Backend() = lapack.Name()

-- n evenly spaced floats from a to b, both included.
--
--   Linspace(0, 1, 3) --> [0.0, 0.5, 1.0]
defn Linspace(a, b, n)
  if n == 1
    return [1.0 * a]
  end
  step = (b - a) / (n - 1)
  [a + k * step for k in 0:n - 1]
end

-- The identity matrix of order n.
--
--   Sum(Eye(2)) --> 2.0
defn Eye(n)
  m = Zeros(n, n)
  for k in 1:n
    m[k, k] = 1.0
  end
  m
end

-- A square matrix with the elements on its diagonal and 0.0 elsewhere.
--
--   Sum(Diag([1, 2])) --> 3.0
defn Diag(xs)
  n = Len(xs)
  m = Zeros(n, n)
  for k in 1:n
    m[k, k] = xs[k]
  end
  m
end

-- The variance of the elements: the mean of the squares of their distance from the mean.
--
--   Variance([1.0, 3.0]) --> 1.0
defn Variance(xs)
  d = xs - Mean(xs)
  Sum(d * d) / Len(xs)
end

-- The standard deviation of the elements.
--
--   Std([1.0, 3.0]) --> 1.0
Std(xs) = Sqrt(Variance(xs))

-- The value below which p percent of the elements fall, interpolating between the two nearest ones.
--
--   Percentile(50, [1.0, 2.0, 3.0]) --> 2.0
defn Percentile(p, xs)
  s = Sort(xs)
  at = p / 100.0 * (Len(s) - 1) + 1
  low = Floor(at)
  high = Ceil(at)
  s[low] + (s[high] - s[low]) * (at - low)
end

-- The middle value of the elements.
--
--   Median([3.0, 1.0, 2.0]) --> 2.0
Median(xs) = Percentile(50, xs)

-- The running sum of the elements.
--
--   Cumsum([1.0, 2.0, 3.0]) --> [1.0, 3.0, 6.0]
defn Cumsum(xs)
  out = Zeros(1, Len(xs))
  total = 0.0
  for k in 1:Len(xs)
    total += xs[k]
    out[k] = total
  end
  out
end

-- The differences between consecutive elements.
--
--   Diff([1, 4, 9]) --> [3, 5]
Diff(xs) = [xs[k + 1] - xs[k] for k in 1:Len(xs) - 1]
-- The dot product of two arrays.
--
--   Dot([1, 2], [3, 4]) --> 11
Dot(a, b) = Sum(a * b)
-- The Euclidean length of an array.
--
--   Norm([3.0, 4.0]) --> 5.0
Norm(xs) = Sqrt(Dot(xs, xs))

-- The covariance of two arrays of the same length.
--
--   Abs(Covariance([1.0, 2.0, 3.0], [2.0, 4.0, 6.0]) - 4.0 / 3.0) < 1e-9 --> true
defn Covariance(a, b)
  Mean((a - Mean(a)) * (b - Mean(b)))
end

-- The correlation of two arrays of the same length, from -1 to 1.
--
--   Abs(Correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.0]) - 1.0) < 1e-9 --> true
Correlation(a, b) = Covariance(a, b) / (Std(a) * Std(b))

-- The elements counted in a number of equal bins, as a struct with counts and edges.
--
--   Histogram(2, [1, 2, 3, 4]).Counts --> [2, 2]
defn Histogram(bins, xs)
  low = Min(xs)
  high = Max(xs)
  width = (high - low) / bins
  counts = Fill(0, bins)
  for x in xs
    k = if width == 0.0 1 else Min(Floor((x - low) / width) + 1, bins) end
    counts[k] += 1
  end
  {Counts: counts, Edges: [low + k * width for k in 0:bins]}
end

-- The sum of each row, and of each column.
SumRows(m) = [Sum(m[i, :]) for i in 1:Size(m, 1)]
-- The sum of each column of a matrix.
--
--   SumCols(Eye(2)) --> [1.0, 1.0]
SumCols(m) = [Sum(m[:, j]) for j in 1:Size(m, 2)]

-- Gaussian elimination with partial pivoting: the triangle, the swaps and their sign.
defn eliminate(m, b)
  n = Size(m, 1)
  sign = 1.0
  for col in 1:n
    pivot = col
    for r in col + 1:n
      if Abs(m[r, col]) > Abs(m[pivot, col])
        pivot = r
      end
    end
    if Abs(m[pivot, col]) < 1e-14
      return {Singular: true, M: m, B: b, Sign: 0.0}
    end
    if pivot != col
      sign = -sign
      for c in 1:n
        t = m[col, c]
        m[col, c] = m[pivot, c]
        m[pivot, c] = t
      end
      for c in 1:Size(b, 2)
        t = b[col, c]
        b[col, c] = b[pivot, c]
        b[pivot, c] = t
      end
    end
    for r in col + 1:n
      f = m[r, col] / m[col, col]
      if f != 0.0
        for c in col:n
          m[r, c] = m[r, c] - f * m[col, c]
        end
        for c in 1:Size(b, 2)
          b[r, c] = b[r, c] - f * b[col, c]
        end
      end
    end
  end
  {Singular: false, M: m, B: b, Sign: sign}
end

-- The determinant of a square matrix.
--
--   Abs(Det(Reshape([1.0, 3.0, 2.0, 4.0], 2, 2)) + 2.0) < 1e-9 --> true
defn Det(m)
  fast = lapack.Det(m)
  if not IsMissing(fast)
    return fast
  end
  t = eliminate(m, Zeros(Size(m, 1), 1))
  if t.Singular
    return 0.0
  end
  d = t.Sign
  for k in 1:Size(m, 1)
    d = d * t.M[k, k]
  end
  d
end

defn back(t)
  n = Size(t.M, 1)
  x = t.B
  for c in 1:Size(x, 2)
    for r in Range(n, 1, step = -1)
      s = x[r, c]
      for k in r + 1:n
        s = s - t.M[r, k] * x[k, c]
      end
      x[r, c] = s / t.M[r, r]
    end
  end
  x
end

singular() = Err({Kind: "math", Message: "This matrix is singular."})

-- x of a x = b, with a library for a large a. b has as many rows as a.
defn solved(m, b)
  fast = lapack.Solve(m, b)
  if not IsMissing(fast)
    return if IsArray(fast) Ok(fast) else singular() end
  end
  t = eliminate(m, b)
  if t.Singular singular() else Ok(back(t)) end
end

-- The x of m * x = b, in an Ok, or an Err of the kind "math" if the matrix is singular.
--
--   Solve(Eye(2), [1.0, 2.0]).Value --> [1.0, 2.0]
defn Solve(m, b)
  n = Size(m, 1)
  MapOk(x -> Reshape(x, 1, n), solved(m, Reshape(b, n, 1)))
end

-- The inverse of a square matrix, in an Ok, or an Err of the kind "math" if it is singular.
--
--   Sum(Inverse(Eye(2)).Value) --> 2.0
Inverse(m) = solved(m, Eye(Size(m, 1)))

-- Gram-Schmidt, twice for accuracy.
defn Qr(m)
  fast = lapack.Qr(m)
  if not IsMissing(fast)
    return fast
  end
  rows = Size(m, 1)
  cols = Size(m, 2)
  q = Zeros(rows, cols)
  r = Zeros(cols, cols)
  for j in 1:cols
    v = m[:, j]
    for pass in 1:2
      for i in 1:j - 1
        qi = q[:, i]
        c = Dot(qi, v)
        r[i, j] = r[i, j] + c
        v = v - qi * c
      end
    end
    sizeV = Norm(v)
    r[j, j] = sizeV
    for i in 1:rows
      q[i, j] = if sizeV == 0.0 0.0 else v[i] / sizeV end
    end
  end
  {Q: q, R: r}
end

-- The eigenvalues and eigenvectors of a symmetric matrix, by Jacobi rotations.
defn Eigen(a)
  fast = lapack.Eigen(a)
  if not IsMissing(fast)
    return fast
  end
  n = Size(a, 1)
  v = Eye(n)
  for sweep in 1:60
    off = 0.0
    for p in 1:n
      for q in p + 1:n
        off += a[p, q] * a[p, q]
      end
    end
    if off < 1e-22
      break
    end
    for p in 1:n
      for q in p + 1:n
        if Abs(a[p, q]) > 1e-300
          theta = (a[q, q] - a[p, p]) / (2.0 * a[p, q])
          t = Sign(theta) / (Abs(theta) + Sqrt(theta * theta + 1.0))
          t = if theta == 0.0 1.0 else t end
          c = 1.0 / Sqrt(t * t + 1.0)
          s = t * c
          for k in 1:n
            akp = a[k, p]
            akq = a[k, q]
            a[k, p] = c * akp - s * akq
            a[k, q] = s * akp + c * akq
          end
          for k in 1:n
            apk = a[p, k]
            aqk = a[q, k]
            a[p, k] = c * apk - s * aqk
            a[q, k] = s * apk + c * aqk
          end
          for k in 1:n
            vkp = v[k, p]
            vkq = v[k, q]
            v[k, p] = c * vkp - s * vkq
            v[k, q] = s * vkp + c * vkq
          end
        end
      end
    end
  end
  {Values: [a[k, k] for k in 1:n], Vectors: v}
end

-- The x of the smallest |ax - b|, through the normal equations.
defn LeastSquares(a, b)
  t = Transpose(a)
  Solve(Matmul(t, a), Matmul(t, Reshape(b, Len(b), 1)))
end

-- The coefficients of a polynomial of a degree through points, the constant first.
defn Polyfit(degree, xs, ys)
  a = Zeros(Len(xs), degree + 1)
  for i in 1:Len(xs)
    for j in 1:degree + 1
      a[i, j] = 1.0 * xs[i] ^ (j - 1)
    end
  end
  Unwrap(LeastSquares(a, ys))
end

-- The value of a polynomial at x, given its coefficients with the constant first.
--
--   Polyval([1, 2], 3) --> 7.0
defn Polyval(coefficients, x)
  total = 0.0
  for k in Range(Len(coefficients), 1, step = -1)
    total = total * x + coefficients[k]
  end
  total
end

-- The area under the points (xs, ys), by the trapezoid rule.
--
--   Trapezoid([0, 1], [0, 2]) --> 1.0
defn Trapezoid(xs, ys)
  total = 0.0
  for k in 1:Len(xs) - 1
    total += (xs[k + 1] - xs[k]) * (ys[k] + ys[k + 1]) / 2.0
  end
  total
end

-- The value at x of the line through the nearest points of (xs, ys), which are sorted by xs. Past the last point it gives the last y.
--
--   Interpolate(0.5, [0, 1], [0, 2]) --> 1.0
defn Interpolate(x, xs, ys)
  for k in 1:Len(xs) - 1
    if x <= xs[k + 1]
      return ys[k] + (ys[k + 1] - ys[k]) * (x - xs[k]) / (xs[k + 1] - xs[k])
    end
  end
  ys[Len(ys)]
end

-- A discrete Fourier transform: radix 2 for powers of two, the plain sum otherwise. Parts are separate arrays.
defn dft(re, im, direction)
  n = Len(re)
  outRe = Zeros(1, n)
  outIm = Zeros(1, n)
  for k in 1:n
    for t in 1:n
      angle = direction * 2.0 * Pi * (k - 1) * (t - 1) / n
      c = Cos(angle)
      s = Sin(angle)
      outRe[k] = outRe[k] + re[t] * c - im[t] * s
      outIm[k] = outIm[k] + re[t] * s + im[t] * c
    end
  end
  {Re: outRe, Im: outIm}
end

defn radix2(re, im, direction)
  n = Len(re)
  if n == 1
    return {Re: re, Im: im}
  end
  half = Div(n, 2)
  even = radix2([re[2 * k - 1] for k in 1:half], [im[2 * k - 1] for k in 1:half], direction)
  odd = radix2([re[2 * k] for k in 1:half], [im[2 * k] for k in 1:half], direction)
  outRe = Zeros(1, n)
  outIm = Zeros(1, n)
  for k in 1:half
    angle = direction * 2.0 * Pi * (k - 1) / n
    c = Cos(angle)
    s = Sin(angle)
    tr = odd.Re[k] * c - odd.Im[k] * s
    ti = odd.Re[k] * s + odd.Im[k] * c
    outRe[k] = even.Re[k] + tr
    outIm[k] = even.Im[k] + ti
    outRe[k + half] = even.Re[k] - tr
    outIm[k + half] = even.Im[k] - ti
  end
  {Re: outRe, Im: outIm}
end

isPower(n) = n > 0 and BitAnd(n, n - 1) == 0

defn transform(re, im, direction)
  if isPower(Len(re)) radix2(re, im, direction) else dft(re, im, direction) end
end

-- The Fourier transform of an array, as a struct with re and im.
--
--   Fft([1.0, 0.0, 0.0, 0.0]).Re --> [1.0, 1.0, 1.0, 1.0]
Fft(xs) = transform(xs, Zeros(1, Len(xs)), -1.0)

-- The inverse of fft, from a struct with re and im.
defn Ifft(f)
  r = transform(f.Re, f.Im, 1.0)
  n = 1.0 * Len(f.Re)
  {Re: r.Re / n, Im: r.Im / n}
end

-- Random numbers that a seed repeats, for simulations: xorshift, never for secrets. A generator is a value.
Seeded(seed) = {State: BitOr(BitXor(seed, 88172645463325252), 1)}

defn next(state)
  x = state
  x = BitXor(x, BitShift(x, 13))
  x = BitXor(x, BitShift(x, -7))
  BitXor(x, BitShift(x, 17))
end

-- n floats in [0, 1) from a generator, as a struct with values and the next generator. See seeded.
--
--   Len(Uniform(3, Seeded(1)).Values) --> 3
defn Uniform(n, generator)
  values = Zeros(1, n)
  s = generator.State
  for k in 1:n
    s = next(s)
    values[k] = BitAnd(s, 1099511627775) / 1099511627776.0
  end
  {Values: values, Next: {State: s}}
end

-- n floats from the normal distribution (mean 0, deviation 1) from a generator, as a struct with values and the next generator.
--
--   Len(Normal(3, Seeded(1)).Values) --> 3
defn Normal(n, generator)
  u = Uniform(2 * n, generator)
  values = Zeros(1, n)
  for k in 1:n
    a = 1.0 - u.Values[2 * k - 1]
    b = u.Values[2 * k]
    values[k] = Sqrt(-2.0 * Log(a)) * Cos(2.0 * Pi * b)
  end
  {Values: values, Next: u.Next}
end
