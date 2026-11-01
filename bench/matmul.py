def matmul(n):
    a = [0.0] * (n * n)
    b = [0.0] * (n * n)
    c = [0.0] * (n * n)
    for i in range(n):
        for j in range(n):
            a[i * n + j] = (i + j) * 0.5
            b[i * n + j] = (i - j) * 0.25
    for i in range(n):
        for j in range(n):
            s = 0.0
            for k in range(n):
                s = s + a[i * n + k] * b[k * n + j]
            c[i * n + j] = s
    return c[n + 1]
print(f"{matmul(300):.6f}")
