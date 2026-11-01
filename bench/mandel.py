def mandel(w, h, maxit):
    total = 0
    for py in range(h):
        y0 = 2.0 * py / h - 1.0
        for px in range(w):
            x0 = 3.0 * px / w - 2.0
            x = y = x2 = y2 = 0.0
            it = 0
            while x2 + y2 < 4.0 and it < maxit:
                y = 2.0 * x * y + y0
                x = x2 - y2 + x0
                x2 = x * x
                y2 = y * y
                it += 1
            total += it
    return total
print(mandel(600, 400, 200))
