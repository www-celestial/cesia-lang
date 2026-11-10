class matmul {
  static double matmul(int n) {
    double[] a = new double[n * n], b = new double[n * n], c = new double[n * n];
    for (int i = 0; i < n; i++)
      for (int j = 0; j < n; j++) {
        a[i * n + j] = (i + j) * 0.5;
        b[i * n + j] = (i - j) * 0.25;
      }
    for (int i = 0; i < n; i++)
      for (int j = 0; j < n; j++) {
        double s = 0.0;
        for (int k = 0; k < n; k++) s = s + a[i * n + k] * b[k * n + j];
        c[i * n + j] = s;
      }
    return c[n + 1];
  }
  public static void main(String[] a) { System.out.println(String.format(java.util.Locale.ROOT, "%.6f", matmul(300))); }
}
