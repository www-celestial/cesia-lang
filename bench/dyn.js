function dyn(n) {
  const ops = [(a, b) => a + b, (a, b) => a * 0.5 + b];
  const xs = [1, 2.5, 3, 4.5];
  let total = 0.0;
  for (let i = 1; i <= n; i++) {
    const f = ops[i % 2];
    const x = xs[i % 4];
    total = f(total, x);
    if (total > 1000000.0) total = total / 2;
  }
  return total;
}
console.log(dyn(10000000).toFixed(6));
