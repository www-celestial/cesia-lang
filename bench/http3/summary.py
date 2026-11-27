#!/usr/bin/env python3
"""summary.py [RESULTS_DIR]: the tables of bench/http3, each value the median over the rounds [min, max].

Reads the JSON lines that rps.sh, download.sh, memory.sh, ab.sh and migrate.sh wrote ($HOME/.cache/quic/bench/results
by default) and prints Markdown tables."""

import json
import math
import os
import statistics
import sys
from collections import defaultdict

RES = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.cache/quic/bench/results")
PROFILES = {"clean": "clean", "d25l1": "25 ms + 1 % (RTT 50 ms)", "d50l3": "50 ms + 3 % (RTT 100 ms)",
            "d100l5": "100 ms + 5 % (RTT 200 ms)"}
SERVERS = ["cesia", "quicgo", "caddy", "nginx"]
PROTOS = ["h1", "h2", "h3"]


def lines(name):
    path = os.path.join(RES, name)
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(x) for x in f if x.strip()]


def mmm(values, fmt="{:.0f}"):
    """median [min, max] of the values, or '-' when there are none."""
    v = [x for x in values if x is not None]
    if not v:
        return "-"
    return f"{fmt.format(statistics.median(v))} [{fmt.format(min(v))}, {fmt.format(max(v))}]"


def load1(rows):
    return mmm([float(r["loadavg"].split()[0]) for r in rows if "loadavg" in r], "{:.1f}")


def wilcoxon(ratios):
    """The two-sided p of Wilcoxon's signed-rank test on the logarithms of paired ratios (normal approximation, ties
    averaged): is one side faster in the rounds, beyond what the noise shared by both sides of a round explains?"""
    d = [math.log(r) for r in ratios if r != 1]
    n = len(d)
    if n < 6:
        return float("nan")
    ranked = sorted(abs(x) for x in d)
    rank = {}
    i = 0
    while i < n:
        j = i
        while j + 1 < n and ranked[j + 1] == ranked[i]:
            j += 1
        for k in range(i, j + 1):
            rank[ranked[k]] = (i + j) / 2 + 1
        i = j + 1
    w = sum(rank[abs(x)] for x in d if x > 0)
    mu, sd = n * (n + 1) / 4, math.sqrt(n * (n + 1) * (2 * n + 1) / 24)
    return math.erfc(abs(w - mu) / sd / math.sqrt(2))


def table(head, rows):
    print("| " + " | ".join(head) + " |")
    print("|" + "|".join("---" for _ in head) + "|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    print()


def rps():
    for prof, title in PROFILES.items():
        data = lines(f"rps-{prof}.jsonl")
        if not data:
            continue
        for c in sorted({d["c"] for d in data}, reverse=True):
            groups = defaultdict(list)
            for d in data:
                if d["c"] == c:
                    groups[(d["server"], d["proto"])].append(d)
            rounds = max(len(v) for v in groups.values())
            print(f"### GET / requests/s, {title}, -c {c}, {rounds} rounds\n")
            rows = []
            for s in SERVERS:
                for p in PROTOS:
                    g = groups.get((s, p))
                    if g:
                        rows.append([s, p, mmm([d["rps"] for d in g]), mmm([d["p50_ms"] for d in g], "{:.2f}"),
                                     mmm([d["p99_ms"] for d in g], "{:.2f}"), sum(d["errors"] for d in g),
                                     load1(g)])
            table(["server", "proto", "req/s", "p50 ms", "p99 ms", "errors", "load avg (1 min)"], rows)


def download():
    for prof, title in PROFILES.items():
        data = lines(f"download-{prof}.jsonl")
        if not data:
            continue
        for size in sorted({d["bytes"] for d in data}):
            groups = defaultdict(list)
            for d in data:
                if d["bytes"] == size:
                    groups[(d["server"], d["proto"])].append(d)
            print(f"### Download of {size // 1000000} MB, new connection each, {title}\n")
            rows = []
            for s in SERVERS:
                for p in PROTOS:
                    g = groups.get((s, p))
                    if g:
                        ok = [d for d in g if d.get("downloads", 0) > 0]
                        rows.append([s, p, mmm([d.get("ms") for d in ok], "{:.1f}"),
                                     mmm([d.get("ttfb_ms") for d in ok], "{:.1f}"),
                                     mmm([d.get("mb_s") for d in ok], "{:.1f}"),
                                     f"{sum(d['downloads'] for d in g)} / {sum(d['errors'] for d in g)}", load1(g)])
            table(["server", "proto", "ms per download", "first byte ms", "MB/s", "downloads / errors",
                   "load avg"], rows)


def memory():
    data = lines("memory.jsonl")
    if not data:
        return
    groups = defaultdict(list)
    for d in data:
        groups[(d["server"], d["proto"])].append(d)
    n = data[0]["n"]
    print(f"### Server memory per idle connection ({n} connections, one GET each, idle 3 s), clean\n")
    rows = []
    for (s, p), g in sorted(groups.items(), key=lambda kv: (SERVERS.index(kv[0][0]), kv[0][1])):
        rows.append([s, p, mmm([d["per_conn_kb"] for d in g], "{:.1f}"), mmm([d["before_kb"] / 1024 for d in g],
                     "{:.1f}"), mmm([d["after_kb"] / 1024 for d in g], "{:.1f}"),
                     f"{min(d['open'] for d in g)}-{max(d['open'] for d in g)}", len(g)])
    table(["server", "proto", "KB per connection", "RSS before MB", "RSS after MB", "connections open", "rounds"],
          rows)


def ab():
    data = lines("ab.jsonl")
    if not data:
        return
    print(f"### A/B of Cesia's TCP path (HTTPS HTTP/1.1, GET /, -c 16, clean), {len(data) // 2} rounds\n")
    rows = []
    for b in ["main", "quic"]:
        g = [d for d in data if d["binary"] == b]
        rows.append([b, mmm([d["rps"] for d in g]), mmm([d["p50_ms"] for d in g], "{:.3f}"),
                     mmm([d["p99_ms"] for d in g], "{:.2f}"), sum(d["errors"] for d in g), load1(g)])
    table(["binary", "req/s", "p50 ms", "p99 ms", "errors", "load avg"], rows)
    by = defaultdict(dict)
    for d in data:
        by[d["round"]][d["binary"]] = d["rps"]
    ratios = [v["quic"] / v["main"] for v in by.values() if "quic" in v and "main" in v]
    if ratios:
        print(f"quic / main req/s, paired by round: {mmm(ratios, '{:.3f}')}, Wilcoxon p = {wilcoxon(ratios):.2g}\n")


def h3off():
    data = lines("h3off.jsonl")
    if not data:
        return
    print(f"### Cesia HTTPS HTTP/1.1 with serve.ce's HTTP/3 off or on (GET /, -c 16, clean), {len(data) // 2} rounds\n")
    rows = []
    for h in ["off", "on"]:
        g = [d for d in data if d["http3"] == h]
        rows.append([h, mmm([d["rps"] for d in g]), mmm([d["p50_ms"] for d in g], "{:.3f}"),
                     mmm([d["p99_ms"] for d in g], "{:.2f}"), sum(d["errors"] for d in g), load1(g)])
    table(["HTTP/3 beside", "req/s", "p50 ms", "p99 ms", "errors", "load avg"], rows)
    by = defaultdict(dict)
    for d in data:
        by[d["round"]][d["http3"]] = d["rps"]
    ratios = [v["on"] / v["off"] for v in by.values() if "on" in v and "off" in v]
    if ratios:
        print(f"on / off req/s, paired by round: {mmm(ratios, '{:.3f}')}, Wilcoxon p = {wilcoxon(ratios):.2g}\n")


def migrate():
    for prof, title in PROFILES.items():
        data = lines(f"migrate-{prof}.jsonl")
        if not data:
            continue
        groups = defaultdict(list)
        for d in data:
            groups[(d["server"], d["proto"], d["how"])].append(d)
        print(f"### Address change after 2 MB of a 10 MB download, {title}\n")
        rows = []
        for (s, p, how), g in sorted(groups.items(), key=lambda kv: (kv[0][1] != "h3", kv[0][2], kv[0][0])):
            outcomes = sorted({d.get("outcome") or "error: " + d.get("error", "?")[:60] for d in g})
            rows.append([s, p, how, mmm([d.get("continue_ms") for d in g], "{:.1f}"),
                         mmm([d.get("total_ms") for d in g], "{:.0f}"), "; ".join(outcomes), len(g)])
        table(["server", "proto", "client does", "change to next byte ms", "whole 10 MB ms", "outcome", "runs"],
              rows)


def crashes():
    data = lines("crashes.jsonl")
    if not data:
        return
    print("### Server crashes seen right after a run\n")
    counts = defaultdict(int)
    for d in data:
        args = d["args"].split()
        mode = next((a.lstrip("-") for a in args if a in ("-download", "-hold", "-migrate")), "load")
        proto = args[args.index("-proto") + 1] if "-proto" in args else "?"
        counts[(d["server"], d.get("profile", ""), proto, mode)] += 1
    table(["server", "profile", "proto", "mode", "crashes"], [list(k) + [v] for k, v in sorted(counts.items())])


if __name__ == "__main__":
    rps()
    download()
    memory()
    ab()
    h3off()
    migrate()
    crashes()
