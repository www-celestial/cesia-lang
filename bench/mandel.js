function mandel(w, h, maxit) {
  let total = 0;
  for (let py = 0; py <= h - 1; py++) {
    const y0 = 2.0 * py / h - 1.0;
    for (let px = 0; px <= w - 1; px++) {
      const x0 = 3.0 * px / w - 2.0;
      let x = 0.0, y = 0.0, x2 = 0.0, y2 = 0.0, it = 0;
      while (x2 + y2 < 4.0 && it < maxit) {
        y = 2.0 * x * y + y0;
        x = x2 - y2 + x0;
        x2 = x * x;
        y2 = y * y;
        it = it + 1;
      }
      total = total + it;
    }
  }
  return total;
}
console.log(mandel(600, 400, 200));
