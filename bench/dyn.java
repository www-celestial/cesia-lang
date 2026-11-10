import java.util.function.DoubleBinaryOperator;
class dyn {
  static double dyn(int n) {
    DoubleBinaryOperator[] ops = { (a, b) -> a + b, (a, b) -> a * 0.5 + b };
    double[] xs = { 1, 2.5, 3, 4.5 };
    double total = 0.0;
    for (int i = 1; i <= n; i++) {
      DoubleBinaryOperator f = ops[i % 2];
      double x = xs[i % 4];
      total = f.applyAsDouble(total, x);
      if (total > 1000000.0) total = total / 2;
    }
    return total;
  }
  public static void main(String[] a) { System.out.println(String.format(java.util.Locale.ROOT, "%.6f", dyn(10000000))); }
}
