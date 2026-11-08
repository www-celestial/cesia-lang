function maps(n) {
  const m = new Map();
  for (let k = 1; k <= n; k++) m.set("key" + k, k);
  let total = 0;
  for (let k = 1; k <= n; k++) total += m.get("key" + k);
  return total;
}
console.log(maps(500000));
