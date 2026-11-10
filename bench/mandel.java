class mandel {
  static long mandel(int w, int h, int maxit) {
    long total = 0;
    for (int py = 0; py <= h - 1; py++) {
      double y0 = 2.0 * py / h - 1.0;
      for (int px = 0; px <= w - 1; px++) {
        double x0 = 3.0 * px / w - 2.0;
        double x = 0.0, y = 0.0, x2 = 0.0, y2 = 0.0;
        int it = 0;
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
  public static void main(String[] a) { System.out.println(mandel(600, 400, 200)); }
}
