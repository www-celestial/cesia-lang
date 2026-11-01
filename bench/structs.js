function simulate(n, steps) {
  const ps = new Array(n);
  for (let i = 1; i <= n; i++) ps[i - 1] = {x: i * 1.0, y: 0.0, vx: 1.0, vy: i * 0.5};
  const dt = 0.001;
  for (let s = 1; s <= steps; s++) {
    for (let i = 0; i < n; i++) {
      const p = ps[i];
      const vy = p.vy - 9.81 * dt;
      ps[i] = {x: p.x + p.vx * dt, y: p.y + vy * dt, vx: p.vx, vy: vy};
    }
  }
  let e = 0.0;
  for (const p of ps) e = e + p.x + p.y;
  return e;
}
console.log(simulate(1000, 5000).toFixed(6));
