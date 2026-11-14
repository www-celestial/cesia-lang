# The export of bench/csv.ce in Python: csv.writer into a StringIO, and date.isoformat, the best of 5.
import csv, io, time, datetime
rows = [[f"INV-{k}", f"Client {k % 997}", "paid", k * 13 % 100000, f"2026-11-{1 + k % 28}", "EUR", f"note, {k}"] for k in range(1, 100001)]
days = [datetime.date(2026, 1 + k % 12, 1 + k % 28) for k in range(1, 100001)]
def best(f):
    t = []
    for _ in range(5):
        s = time.perf_counter(); f(); t.append(time.perf_counter() - s)
    return min(t)
def text():
    out = io.StringIO(); csv.writer(out, lineterminator="\n").writerows(rows); return out.getvalue()
print("python csv us/row:", best(text) * 10, "isoformat us/date:", best(lambda: [d.isoformat() for d in days]) * 10)
