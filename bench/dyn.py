def dyn(n):
    ops = [lambda a, b: a + b, lambda a, b: a * 0.5 + b]
    xs = [1, 2.5, 3, 4.5]
    total = 0.0
    for i in range(1, n + 1):
        f = ops[i % 2]
        x = xs[i % 4]
        total = f(total, x)
        if total > 1000000.0:
            total = total / 2
    return total
print(f"{dyn(10000000):.6f}")
