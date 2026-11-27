# The picture of a lossy download, from the measures of stacks.sh and lossy.sh: one download of 1 MB on a new connection
# over 25 ms each way and 1 % lost, for each QUIC stack (and TCP), the median of the rounds and the line from the least
# to the most. python3 -I lossy-svg.py OUT.svg [fr] RESULTS.jsonl...
import json, statistics, sys

fr = len(sys.argv) > 2 and sys.argv[2] == "fr"
files = sys.argv[3:] if fr else sys.argv[2:]
rows = {}
for f in files:
    for line in open(f):
        m = json.loads(line)
        if "ms" not in m or m.get("errors"):
            continue
        rows.setdefault((m["server"], m["proto"]), []).append(m["ms"] / 1000)

names = {
    ("cesia", "h3"): ("Cesia, HTTP/3 (OpenSSL 4.1's QUIC)", "Cesia, HTTP/3 (le QUIC d’OpenSSL 4.1)"),
    ("bare", "h3"): ("OpenSSL 4.1's QUIC alone, its own loop", "Le QUIC d’OpenSSL 4.1 seul, sa propre boucle"),
    ("bare", "bare-get"): ("OpenSSL 4.1 on both sides", "OpenSSL 4.1 des deux côtés"),
    ("nginx", "h3"): ("nginx 1.27, HTTP/3", "nginx 1.27, HTTP/3"),
    ("ngtcp2-reno", "h3"): ("ngtcp2 1.26, Reno", "ngtcp2 1.26, Reno"),
    ("ngtcp2-cubic", "h3"): ("ngtcp2 1.26, CUBIC", "ngtcp2 1.26, CUBIC"),
    ("ngtcp2-bbr", "h3"): ("ngtcp2 1.26, BBR", "ngtcp2 1.26, BBR"),
    ("caddy", "h3"): ("Caddy (quic-go), HTTP/3", "Caddy (quic-go), HTTP/3"),
    ("quicgo", "h3"): ("quic-go 0.66, HTTP/3", "quic-go 0.66, HTTP/3"),
    ("cesia", "h1"): ("Cesia, HTTP/1.1 over TCP (Linux CUBIC)", "Cesia, HTTP/1.1 sur TCP (CUBIC de Linux)"),
}
picked = [(names[k][1 if fr else 0], k, sorted(rows[k])) for k in names if k in rows]
T = {"title": ("Un téléchargement de 1 Mo, 25 ms dans chaque sens, 1 % des paquets perdus" if fr else
               "A download of 1 MB, 25 ms each way, 1 % of the packets lost"),
     "sub": ("une nouvelle connexion à chaque fois, le client est quic-go ; médiane des tours, la ligne du plus court au plus long" if fr else
             "a new connection each time, the client is quic-go's; median of the rounds, the line from the least to the most"),
     "foot": ("Le QUIC d’OpenSSL : NewReno seul, dont la fenêtre ne grandit ici que d’un paquet tous les 2 à 5 allers-retours, des paquets de 1 200 octets, sans pacing." if fr else
              "OpenSSL's QUIC: NewReno alone, whose window grows here by one packet every 2 to 5 round trips, packets of 1,200 bytes, no pacing."),
     "s": " s"}
W, top, line = 760, 64, 28
# The footnote on lines of at most 105 characters.
foot = [""]
for w in T["foot"].split():
    foot[-1:] = [foot[-1], w] if len(foot[-1]) + len(w) > 105 else [f"{foot[-1]} {w}".strip()]
H = top + line * len(picked) + 34 + 16 * len(foot)
most = max([xs[-1] for _, _, xs in picked] + [1])
scale = 250 / most
o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
     f'<title>{T["title"]}</title>',
     '<style>text{font-family:system-ui, sans-serif;font-size:12px;fill:#1f2328}.h{font-weight:600;font-size:13px}.s{fill:#57606a}'
     '.b{fill:#e7f5ff;stroke:#1971c2}.c{fill:#fff4e6;stroke:#e8590c}.r{stroke:#57606a;stroke-width:1.2}</style>',
     f'<rect width="{W}" height="{H}" fill="#fff"/>',
     f'<text class="h" x="16" y="24">{T["title"]}</text>',
     f'<text class="s" x="16" y="42">{T["sub"]}</text>']
y = top
for label, k, xs in picked:
    med = statistics.median(xs)
    o.append(f'<text x="16" y="{y + 14}">{label}</text>')
    x0 = 330
    cls = "c" if k[0] in ("cesia", "bare") and k[1] != "h1" else "b"
    o.append(f'<rect class="{cls}" x="{x0}" y="{y + 2}" width="{max(2, med * scale):.1f}" height="16" rx="2"/>')
    o.append(f'<line class="r" x1="{x0 + xs[0] * scale:.1f}" y1="{y + 10}" x2="{x0 + xs[-1] * scale:.1f}" y2="{y + 10}"/>')
    at = x0 + max(2, med * scale, xs[-1] * scale) + 6
    o.append(f'<text x="{at:.1f}" y="{y + 14}">{med:.2f} s [{xs[0]:.2f}, {xs[-1]:.2f}], n = {len(xs)}</text>')
    y += line
for i, f in enumerate(foot):
    o.append(f'<text class="s" x="16" y="{y + 20 + 16 * i}">{f}</text>')
o.append('</svg>')
open(sys.argv[1], "w").write("\n".join(o) + "\n")
