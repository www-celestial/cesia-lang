import java.util.concurrent.CountDownLatch;
// COUNT virtual threads park on one latch, then all end once it opens.
class fibers {
  public static void main(String[] a) throws Exception {
    int count = Integer.parseInt(a[0]);
    CountDownLatch gate = new CountDownLatch(1);
    Thread[] ts = new Thread[count];
    for (int i = 0; i < count; i++) ts[i] = Thread.ofVirtual().start(() -> { try { gate.await(); } catch (InterruptedException e) {} });
    gate.countDown();
    for (Thread t : ts) t.join();
    System.out.println(count);
  }
}
