def simulate(n, steps):
    ps = [{"x": (i + 1) * 1.0, "y": 0.0, "vx": 1.0, "vy": (i + 1) * 0.5} for i in range(n)]
    dt = 0.001
    for s in range(steps):
        for i in range(n):
            p = ps[i]
            vy = p["vy"] - 9.81 * dt
            ps[i] = {"x": p["x"] + p["vx"] * dt, "y": p["y"] + vy * dt, "vx": p["vx"], "vy": vy}
    e = 0.0
    for p in ps:
        e = e + p["x"] + p["y"]
    return e
print(f"{simulate(1000, 5000):.6f}")
