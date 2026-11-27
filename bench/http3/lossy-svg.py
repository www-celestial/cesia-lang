# The picture of a lossy download, from the measures of stacks.sh (and of every stack with the profile d25l1r20): one
# download of 1 MB on a new connection over 25 ms each way and 1 % lost (d25l1), or the same through a bottleneck of
# 20 Mbit/s (d25l1r20), for each QUIC stack (and TCP), the median of the rounds and the line from the least to the
# most; the profile is the one of the results. python3 -I lossy-svg.py OUT.svg [fr] RESULTS.jsonl...
import json, statistics, sys

fr = len(sys.argv) > 2 and sys.argv[2] == "fr"
files = sys.argv[3:] if fr else sys.argv[2:]
rows = {}
profiles = set()
for f in files:
    for line in open(f):
        m = json.loads(line)
        if "ms" not in m or m.get("errors"):
            continue
        rows.setdefault((m["server"], m["proto"]), []).append(m["ms"] / 1000)
        profiles.add(m.get("profile", "d25l1"))
if len(profiles) != 1:
    sys.exit(f"one profile at a time, not {sorted(profiles)}")
profile = profiles.pop()

names = {
    ("cesia-bbr", "h3"): ("Cesia, HTTP/3 on ngtcp2, BBR (the default)", "Cesia, HTTP/3 sur ngtcp2, BBR (par défaut)"),
    ("cesia", "h3"): ("Cesia, HTTP/3 on ngtcp2, CUBIC", "Cesia, HTTP/3 sur ngtcp2, CUBIC"),
    ("cesia-reno", "h3"): ("Cesia, HTTP/3 on ngtcp2, Reno", "Cesia, HTTP/3 sur ngtcp2, Reno"),
    ("cesia-openssl", "h3"): ("Cesia before, HTTP/3 on OpenSSL's QUIC", "Cesia avant, HTTP/3 sur le QUIC d’OpenSSL"),
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
TITLE = {"d25l1": ("A download of 1 MB, 25 ms each way, 1 % of the packets lost",
                   "Un téléchargement de 1 Mo, 25 ms dans chaque sens, 1 % des paquets perdus"),
         "d25l1r20": ("A download of 1 MB, 25 ms each way, 1 % lost, 20 Mbit/s at most",
                      "Un téléchargement de 1 Mo, 25 ms dans chaque sens, 1 % perdu, 20 Mbit/s au plus"),
         "d100l5": ("A download of 1 MB, 100 ms each way, 5 % of the packets lost",
                    "Un téléchargement de 1 Mo, 100 ms dans chaque sens, 5 % des paquets perdus"),
         "clean": ("A download of 1 MB on a clean link", "Un téléchargement de 1 Mo sur un lien propre")}
FOOT = {"d25l1": ("Cesia's HTTP/3 counts a Retry, one round trip that the others don't make. Pinned to 2 physical cores (server, client), another measure may run on the 2 others.",
                  "Le HTTP/3 de Cesia compte un Retry, un aller-retour que les autres ne font pas. Épinglé sur 2 cœurs physiques (serveur, client), une autre mesure peut tourner sur les 2 autres."),
        "d25l1r20": ("A bottleneck of 20 Mbit/s spaces the packets, as a real path does. Pinned to 2 physical cores, another measure may run on the 2 others.",
                     "Un goulot de 20 Mbit/s espace les paquets, comme un vrai chemin. Épinglé sur 2 cœurs physiques, une autre mesure peut tourner sur les 2 autres."),
        "d100l5": ("100 ms each way and 5 % lost: a poor mobile network. Pinned to 2 physical cores, another measure may run on the 2 others.",
                   "100 ms dans chaque sens et 5 % perdus : un mauvais réseau mobile. Épinglé sur 2 cœurs physiques, une autre mesure peut tourner sur les 2 autres."),
        "clean": ("A clean link of the machine itself. Pinned to 2 physical cores, another measure may run on the 2 others.",
                  "Un lien propre, celui de la machine elle-même. Épinglé sur 2 cœurs physiques, une autre mesure peut tourner sur les 2 autres.")}
T = {"title": TITLE[profile][1 if fr else 0],
     "sub": ("une nouvelle connexion à chaque fois, le client est quic-go ; médiane des tours, la ligne du plus court au plus long" if fr else
             "a new connection each time, the client is quic-go's; median of the rounds, the line from the least to the most"),
     "foot": FOOT[profile][1 if fr else 0],
     "s": " s"}


SEP = " ; " if fr else ", "


def num(x):
    """x with two decimals, a comma in French."""
    t = f"{x:.2f}"
    return t.replace(".", ",") if fr else t
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
    cls = "c" if k[0].startswith("cesia") and k[1] != "h1" else "b"
    o.append(f'<rect class="{cls}" x="{x0}" y="{y + 2}" width="{max(2, med * scale):.1f}" height="16" rx="2"/>')
    o.append(f'<line class="r" x1="{x0 + xs[0] * scale:.1f}" y1="{y + 10}" x2="{x0 + xs[-1] * scale:.1f}" y2="{y + 10}"/>')
    at = x0 + max(2, med * scale, xs[-1] * scale) + 6
    o.append(f'<text x="{at:.1f}" y="{y + 14}">{num(med)} s [{num(xs[0])}{SEP}{num(xs[-1])}], n = {len(xs)}</text>')
    y += line
for i, f in enumerate(foot):
    o.append(f'<text class="s" x="16" y="{y + 20 + 16 * i}">{f}</text>')
o.append('</svg>')
open(sys.argv[1], "w").write("\n".join(o) + "\n")
