function run(n, steps) {
  const ps = new Array(n);
  for (let i = 1; i <= n; i++) ps[i - 1] = {X: i, V: (i % 7) - 3};
  for (let s = 1; s <= steps; s++) for (let i = 0; i < n; i++) { const p = ps[i]; ps[i] = {X: p.X + p.V, V: p.V}; }
  let total = 0;
  for (let i = 0; i < n; i++) total += ps[i].X;
  return total;
}
console.log(run(1000, 2000));
