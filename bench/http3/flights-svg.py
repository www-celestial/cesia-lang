# The picture of what a client of a lossy download receives at each round trip, from quic-go's qlog of the client
# (QLOGDIR): the 1-RTT packets received per 50 ms (one RTT on 25 ms each way), one line per server, for the download
# of each folder whose time is the median of its downloads.
#   python3 -I flights-svg.py OUT.svg [fr] LABEL=QLOG-FOLDER...
import json, os, statistics, sys

fr = len(sys.argv) > 2 and sys.argv[2] == "fr"
pairs = sys.argv[3:] if fr else sys.argv[2:]
BIN = 50.0


def received(path):
    times = []
    for r in open(path, "rb").read().split(b"\x1e"):
        r = r.strip()
        if not r:
            continue
        try:
            e = json.loads(r)
        except ValueError:
            continue
        if e.get("name") == "transport:packet_received" and e.get("data", {}).get("header", {}).get("packet_type") in ("1RTT", "1-RTT"):
            times.append(e["time"])
    return times


series = []
for p in pairs:
    label, folder = p.split("=", 1)
    runs = [received(os.path.join(folder, f)) for f in sorted(os.listdir(folder)) if f.endswith(".sqlog")]
    runs = [r for r in runs if r]
    spans = [r[-1] - r[0] for r in runs]
    med = statistics.median_low(spans)
    times = runs[spans.index(med)]
    t0 = times[0]
    counts = {}
    for t in times:
        counts[int((t - t0) // BIN)] = counts.get(int((t - t0) // BIN), 0) + 1
    last = max(counts)
    series.append((label, [counts.get(b, 0) for b in range(last + 1)], med))

colors = ["#257de0", "#f47230", "#00b894"]
W, H, L, R, T, B = 760, 350, 56, 170, 78, 46
most_t = max(len(s[1]) for s in series) * BIN / 1000
most_n = max(max(s[1]) for s in series)
top_n = 10 * ((most_n + 9) // 10)
x = lambda t: L + (W - L - R) * t / most_t
y = lambda n: T + (H - T - B) * (1 - n / top_n)
title = ("Ce que le client reçoit à chaque aller-retour : 1 Mo, 25 ms dans chaque sens, 1 % perdu" if fr else
         "What the client receives at each round trip: 1 MB, 25 ms each way, 1 % lost")
sub = ("paquets reçus par 50 ms (un aller-retour), d’après le qlog de quic-go côté client ; le téléchargement médian de chacun" if fr else
       "packets received per 50 ms (one round trip), from the client's qlog (quic-go); the median download of each")
o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
     f'<title>{title}</title>',
     '<style>text{font-family:system-ui, sans-serif;font-size:12px;fill:#1f2328}.h{font-weight:600;font-size:13px}'
     '.s{fill:#57606a}.g{stroke:#d0d7de;stroke-width:1}.a{stroke:#57606a;stroke-width:1}</style>',
     f'<rect width="{W}" height="{H}" fill="#fff"/>',
     f'<text class="h" x="16" y="24">{title}</text>', f'<text class="s" x="16" y="42">{sub}</text>']
for n in range(0, top_n + 1, 10):
    o.append(f'<line class="g" x1="{L}" y1="{y(n):.1f}" x2="{W - R}" y2="{y(n):.1f}"/>')
    o.append(f'<text class="s" x="{L - 8}" y="{y(n) + 4:.1f}" text-anchor="end">{n}</text>')
step = 1 if most_t <= 8 else 2
for s in range(0, int(most_t) + 1, step):
    o.append(f'<text class="s" x="{x(s):.1f}" y="{H - B + 18}" text-anchor="middle">{s} s</text>')
o.append(f'<line class="a" x1="{L}" y1="{y(0):.1f}" x2="{W - R}" y2="{y(0):.1f}"/>')
o.append(f'<text class="s" x="{L - 8}" y="{T - 12}" text-anchor="end">{"paquets" if fr else "packets"}</text>')
for i, (label, counts, med) in enumerate(series):
    pts = []
    for b, n in enumerate(counts):
        pts.append(f"{x(b * BIN / 1000):.1f},{y(n):.1f}")
        pts.append(f"{x((b + 1) * BIN / 1000):.1f},{y(n):.1f}")
    o.append(f'<polyline fill="none" stroke="{colors[i]}" stroke-width="2" stroke-linejoin="round" points="{" ".join(pts)}"/>')
    ex, ey = x(len(counts) * BIN / 1000), y(counts[-1])
    o.append(f'<circle cx="{ex:.1f}" cy="{ey:.1f}" r="4" fill="{colors[i]}" stroke="#fff" stroke-width="2"/>')
    # The legend on the right, in the order of the lines: a swatch then the name and the time of that download.
    ly = T + 14 + i * 34
    o.append(f'<rect x="{W - R + 14}" y="{ly - 9}" width="14" height="4" rx="2" fill="{colors[i]}"/>')
    o.append(f'<text x="{W - R + 34}" y="{ly - 3}">{label}</text>')
    secs = f"{med / 1000:.2f}"
    o.append(f'<text class="s" x="{W - R + 34}" y="{ly + 12}">{secs.replace(".", ",") if fr else secs} s</text>')
o.append('</svg>')
open(sys.argv[1], "w").write("\n".join(o) + "\n")
