class structs {
  record P(double x, double y, double vx, double vy) {}
  static double simulate(int n, int steps) {
    P[] ps = new P[n];
    for (int i = 1; i <= n; i++) ps[i - 1] = new P(i * 1.0, 0.0, 1.0, i * 0.5);
    double dt = 0.001;
    for (int s = 1; s <= steps; s++) {
      for (int i = 0; i < n; i++) {
        P p = ps[i];
        double vy = p.vy() - 9.81 * dt;
        ps[i] = new P(p.x() + p.vx() * dt, p.y() + vy * dt, p.vx(), vy);
      }
    }
    double e = 0.0;
    for (P p : ps) e = e + p.x() + p.y();
    return e;
  }
  public static void main(String[] a) { System.out.println(String.format(java.util.Locale.ROOT, "%.6f", simulate(1000, 5000))); }
}
