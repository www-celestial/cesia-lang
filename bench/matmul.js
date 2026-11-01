function matmul(n) {
  const a = new Array(n * n).fill(0.0), b = new Array(n * n).fill(0.0), c = new Array(n * n).fill(0.0);
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      a[i * n + j] = (i + j) * 0.5;
      b[i * n + j] = (i - j) * 0.25;
    }
  }
  for (let i = 0; i < n; i++) {
    for (let j = 0; j < n; j++) {
      let s = 0.0;
      for (let k = 0; k < n; k++) {
        s = s + a[i * n + k] * b[k * n + j];
      }
      c[i * n + j] = s;
    }
  }
  return c[n + 1];
}
console.log(matmul(300).toFixed(6));
