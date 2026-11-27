# The picture of the choice of a congestion control: for each profile of stacks.sh (clean, d25l1, d25l1r20, d100l5),
# the median time of a download of 1 MB on a new connection over Cesia's HTTP/3 with each congestion control of ngtcp2
# (BBR, CUBIC, Reno), beside Cesia on OpenSSL's QUIC as it was and quic-go; each bar its median, the line from the
# least to the most. python3 -I congestion-svg.py OUT.svg [fr] RESULTS.jsonl...
import json, statistics, sys

fr = len(sys.argv) > 2 and sys.argv[2] == "fr"
files = sys.argv[3:] if fr else sys.argv[2:]
rows = {}
for f in files:
    for line in open(f):
        m = json.loads(line)
        if "ms" not in m or m.get("errors") or m.get("proto") != "h3":
            continue
        rows.setdefault((m.get("profile", "d25l1"), m["server"]), []).append(m["ms"] / 1000)

stacks = [("cesia-bbr", "BBR", "BBR", "#1971c2"), ("cesia", "CUBIC", "CUBIC", "#2f9e44"), ("cesia-reno", "Reno", "Reno", "#e8590c"),
          ("cesia-openssl", "OpenSSL's QUIC (before)", "QUIC d’OpenSSL (avant)", "#868e96"), ("quicgo", "quic-go", "quic-go", "#7048e8")]
profiles = [("clean", "clean link", "lien propre"), ("d25l1", "25 ms each way, 1 % lost", "25 ms dans chaque sens, 1 % perdu"),
            ("d25l1r20", "the same, through 20 Mbit/s", "le même, par 20 Mbit/s"),
            ("d100l5", "100 ms each way, 5 % lost", "100 ms dans chaque sens, 5 % perdus")]
profiles = [p for p in profiles if any((p[0], s[0]) in rows for s in stacks)]
title = ("Cesia's HTTP/3 on ngtcp2: which congestion control, by link" if not fr else
         "Le HTTP/3 de Cesia sur ngtcp2 : quel contrôle de congestion, selon le lien")
sub = ("a download of 1 MB on a new connection, the client quic-go's; median of the rounds, the line from the least to the most" if not fr else
       "un téléchargement de 1 Mo sur une nouvelle connexion, le client est quic-go ; médiane des tours, la ligne du plus court au plus long")
foot = ("Pinned to 2 physical cores (server, client); another measure may run on the 2 others. Each scale is its own." if not fr else
        "Épinglé sur 2 cœurs physiques (serveur, client) ; une autre mesure peut tourner sur les 2 autres. Chaque échelle est la sienne.")


def num(x):
    """x in seconds with two decimals, or in milliseconds below 0.1 s; a comma in French."""
    t = f"{x * 1000:.0f} ms" if x < 0.1 else f"{x:.2f} s"
    return t.replace(".", ",") if fr else t


W, top, bar, gap = 760, 64, 20, 18
o = []
y = top
for key, en, fr_name in profiles:
    o.append(f'<text class="h" x="16" y="{y + 12}">{fr_name if fr else en}</text>')
    y += 20
    here = [(s, sorted(rows[(key, s[0])])) for s in stacks if (key, s[0]) in rows]
    most = max(xs[-1] for _, xs in here)
    scale = 330 / most
    for (name, label_en, label_fr, color), xs in here:
        med = statistics.median(xs)
        o.append(f'<text x="32" y="{y + 14}">{label_fr if fr else label_en}</text>')
        x0 = 230
        o.append(f'<rect x="{x0}" y="{y + 3}" width="{max(2, med * scale):.1f}" height="14" rx="2" fill="{color}" fill-opacity="0.25" stroke="{color}"/>')
        o.append(f'<line class="r" x1="{x0 + xs[0] * scale:.1f}" y1="{y + 10}" x2="{x0 + xs[-1] * scale:.1f}" y2="{y + 10}"/>')
        at = x0 + max(2, med * scale, xs[-1] * scale) + 6
        o.append(f'<text x="{at:.1f}" y="{y + 14}">{num(med)}</text>')
        y += bar
    y += gap
H = y + 24
head = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
        f'<title>{title}</title>',
        '<style>text{font-family:system-ui, sans-serif;font-size:12px;fill:#1f2328}.h{font-weight:600;font-size:13px}.s{fill:#57606a}'
        '.r{stroke:#57606a;stroke-width:1.2}</style>',
        f'<rect width="{W}" height="{H}" fill="#fff"/>',
        f'<text class="h" x="16" y="24">{title}</text>',
        f'<text class="s" x="16" y="42">{sub}</text>']
o = head + o + [f'<text class="s" x="16" y="{y + 8}">{foot}</text>', '</svg>']
open(sys.argv[1], "w").write("\n".join(o) + "\n")
