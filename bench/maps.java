import java.util.HashMap;
class maps {
  static long maps(int n) {
    HashMap<String, Integer> m = new HashMap<>();
    for (int k = 1; k <= n; k++) m.put("key" + k, k);
    long total = 0;
    for (int k = 1; k <= n; k++) total += m.get("key" + k);
    return total;
  }
  public static void main(String[] a) { System.out.println(maps(500000)); }
}
