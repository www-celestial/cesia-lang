# stats.py RESULTS.jsonl [A B ...]: per case (server:proto) the median download time, [min, max] and the 95 %
# distribution-free interval of the median (order statistics, binomial); for each pair asked (A then B) the ratio of the
# medians and the Mann-Whitney U test (two-sided, normal approximation with ties). python3 -I stats.py FILE A B C D...
import json, math, statistics, sys

rows = {}
for line in open(sys.argv[1]):
    d = json.loads(line)
    if "ms" not in d or d.get("errors"):
        continue
    rows.setdefault(f"{d['server']}:{d['proto']}", []).append(d["ms"])


def median_ci(xs):
    """Ranks (k, n+1-k) with P(k <= rank of the median <= n+1-k) >= 0.95."""
    n = len(xs)
    s = sorted(xs)
    best = (0, n - 1)
    for k in range(n // 2, -1, -1):
        cover = sum(math.comb(n, i) for i in range(k + 1, n - k)) / 2**n
        if cover >= 0.95:
            best = (k, n - 1 - k)
            break
    return s[best[0]], s[best[1]]


def mann_whitney(a, b):
    both = sorted([(v, 0) for v in a] + [(v, 1) for v in b])
    ranks = [0.0] * len(both)
    i = 0
    ties = 0.0
    while i < len(both):
        j = i
        while j + 1 < len(both) and both[j + 1][0] == both[i][0]:
            j += 1
        r = (i + j) / 2 + 1
        for k in range(i, j + 1):
            ranks[k] = r
        t = j - i + 1
        ties += t**3 - t
        i = j + 1
    n1, n2 = len(a), len(b)
    r1 = sum(r for r, (v, g) in zip(ranks, both) if g == 0)
    u = r1 - n1 * (n1 + 1) / 2
    mu = n1 * n2 / 2
    n = n1 + n2
    sigma = math.sqrt(n1 * n2 / 12 * ((n + 1) - ties / (n * (n - 1))))
    z = (u - mu) / sigma if sigma else 0
    p = math.erfc(abs(z) / math.sqrt(2))
    return u, p


print("| case | n | median ms | [min, max] | 95 % interval of the median |")
print("|---|---|---|---|---|")
for k, xs in rows.items():
    lo, hi = median_ci(xs)
    print(f"| {k} | {len(xs)} | {statistics.median(xs):.0f} | [{min(xs):.0f}, {max(xs):.0f}] | [{lo:.0f}, {hi:.0f}] |")
args = sys.argv[2:]
for a, b in zip(args[::2], args[1::2]):
    if a in rows and b in rows:
        u, p = mann_whitney(rows[a], rows[b])
        ratio = statistics.median(rows[a]) / statistics.median(rows[b])
        print(f"\n{a} vs {b}: medians ratio {ratio:.2f}, Mann-Whitney U {u:.0f}, two-sided p = {p:.2g}")
