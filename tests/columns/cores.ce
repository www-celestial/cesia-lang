-- Large columns go through several cores. The results don't depend on how many, to the last bit.
use columns

base = [Mod(k * 7919, 10007) for k in 1:10007]
ks = Flatten([base for copy in 1:30])
n = Len(ks)
xs = ks / 3.0
Print(columns.Cores())
Print(Sum(xs))
Print(Sum((xs + 1.5) * xs - xs / 3.0))
Print(Sum(Sin(xs)))
Print(Sum(Transpose(Reshape(xs, 3, Div(n, 3)))))
m = Matmul(Reshape(xs[1:40000], 200, 200), Reshape(xs[1:40000], 200, 200))
Print(Sum(m))
o = Order(xs)
Print(o[1], o[n], Sum(Abs(columns.Pick(o, xs) - Sort(xs))) == 0.0)
Print(Sum(Abs(Order(ks) - o)) == 0)
Print(Sum(Abs(columns.Pick(1:n, ks) - ks)) == 0)
Print(columns.Join(ks, 0:10006, false).Right[n])
