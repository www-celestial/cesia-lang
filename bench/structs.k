defn simulate(n, steps)
  ps = Fill(0, n)
  for i in 1:n
    ps[i] = {X: i * 1.0, Y: 0.0, Vx: 1.0, Vy: i * 0.5}
  end
  dt = 0.001
  for s in 1:steps
    for i in 1:n
      p = ps[i]
      vy = p.Vy - 9.81 * dt
      ps[i] = {X: p.X + p.Vx * dt, Y: p.Y + vy * dt, Vx: p.Vx, Vy: vy}
    end
  end
  e = 0.0
  for i in 1:n
    p = ps[i]
    e = e + p.X + p.Y
  end
  e
end
Print(simulate(1000, 5000))
