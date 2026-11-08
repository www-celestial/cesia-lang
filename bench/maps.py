def maps(n):
    m = {}
    for k in range(1, n + 1):
        m[f"key{k}"] = k
    total = 0
    for k in range(1, n + 1):
        total += m[f"key{k}"]
    return total
print(maps(500000))
