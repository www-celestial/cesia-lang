# The picture of a migration, from the measures of migrate.sh: python3 -I migration-svg.py RESULTS-FOLDER OUT.svg [fr]
# A download of 10 MB whose client changes address at 2 MB, on each row a way to carry on: the bytes before the change,
# the pause until the next byte (median of the rounds, [min, max]), and the bytes after it.
import json, statistics, sys

rows = {}
for profile in ("clean", "d25l1"):
    try:
        lines = open(f"{sys.argv[1]}/migrate-{profile}.jsonl").read().splitlines()
    except OSError:
        continue
    for l in lines:
        m = json.loads(l)
        if "continue_ms" not in m or m.get("error"):
            continue
        key = (profile, m["server"], m["proto"], m["how"], m.get("outcome", m["how"]))
        rows.setdefault(key, []).append(m["continue_ms"])

fr = len(sys.argv) > 3 and sys.argv[3] == "fr"
names = {
    ("quicgo", "h3", "migrate"): "QUIC, migration (quic-go both sides)",
    ("cesia-bbr", "h3", "migrate"): "QUIC, migration (Cesia's server on ngtcp2)",
    ("cesia-openssl", "h3", "reconnect"): "QUIC before, a new connection (Cesia on OpenSSL)",
    ("cesia-bbr", "h3", "reconnect"): "QUIC, a new connection and the rest (Cesia)",
    ("quicgo", "h1", "reconnect"): "TCP, a new connection and Range (Go)",
    ("cesia", "h1", "reconnect"): "TCP, a new connection and the rest (Cesia)",
    ("cesia", "h3", "reconnect"): "QUIC, a new connection and the rest (Cesia)",
}
if fr:
    names = {
        ("quicgo", "h3", "migrate"): "QUIC, migration (quic-go des deux côtés)",
        ("cesia-bbr", "h3", "migrate"): "QUIC, migration (le serveur de Cesia sur ngtcp2)",
        ("cesia-openssl", "h3", "reconnect"): "QUIC avant, une nouvelle connexion (Cesia sur OpenSSL)",
        ("cesia-bbr", "h3", "reconnect"): "QUIC, une nouvelle connexion et le reste (Cesia)",
        ("quicgo", "h1", "reconnect"): "TCP, une nouvelle connexion et Range (Go)",
        ("cesia", "h1", "reconnect"): "TCP, une nouvelle connexion et le reste (Cesia)",
        ("cesia", "h3", "reconnect"): "QUIC, une nouvelle connexion et le reste (Cesia)",
    }
T = {"title": "Le client change d\u2019adresse à 2 Mo sur 10 Mo : la pause avant l\u2019octet suivant" if fr else "The client changes address at 2 MB of 10 MB: the pause before the next byte",
     "sub": "médiane des tours, la ligne du plus court au plus long ; migrate.sh, puis python3 -I migration-svg.py" if fr else "median of the rounds, the line from the least to the most; migrate.sh, then python3 -I migration-svg.py",
     "clean": "un lien propre" if fr else "a clean link", "d25": "25 ms dans chaque sens, 1 % perdu" if fr else "25 ms each way, 1 % lost",
     "again": ", reconnecté" if fr else " (it reconnected)",
     "foot": "QUIC avec migration garde sa connexion ; les autres en ouvrent une nouvelle et demandent le reste, comme la reprise de Centauri." if fr else "QUIC with migration keeps its connection; the others open a new one and ask for the rest, as Centauri\u2019s resume does."}
order = list(names)
W, top, line = 760, 64, 30
picked = []
for profile in ("clean", "d25l1"):
    for k in order:
        vs = [v for (p, s, pr, how, out), xs in rows.items() for v in xs if (p, s, pr, how) == (profile, *k)]
        outs = sorted({out for (p, s, pr, how, out) in rows if (p, s, pr, how) == (profile, *k)})
        if vs:
            picked.append((profile, k, statistics.median(vs), min(vs), max(vs), outs))
H = top + line * len(picked) + 70
most = max([p[4] for p in picked] + [1])
scale = 230 / most
o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
     '<title>A download whose client changes address at 2 MB: the pause before the next byte, for each way to carry on</title>',
     '<style>text{font-family:system-ui, sans-serif;font-size:12px;fill:#1f2328}.h{font-weight:600;font-size:13px}.s{fill:#57606a}'
     '.b{fill:#ebfbee;stroke:#2f9e44}.g{fill:#fff4e6;stroke:#e8590c}.r{stroke:#57606a;stroke-width:1.2}</style>',
     f'<rect width="{W}" height="{H}" fill="#fff"/>',
     f'<text class="h" x="16" y="24">{T["title"]}</text>',
     f'<text class="s" x="16" y="42">{T["sub"]}</text>']
y = top
last = None
for profile, k, med, lo, hi, outs in picked:
    if profile != last:
        o.append(f'<text class="h" x="16" y="{y + 4}">{T["clean"] if profile == "clean" else T["d25"]}</text>')
        y += 22
        last = profile
    # A row whose client asked for a migration but made a new connection says so; one that migrated is green.
    migrated = outs == ["migrated"]
    label = names[k] + (T["again"] if k[2] == "migrate" and not migrated else "")
    o.append(f'<text x="16" y="{y + 14}">{label}</text>')
    x0 = 400
    o.append(f'<rect class="{"b" if migrated else "g"}" x="{x0}" y="{y + 2}" width="{max(2, med * scale):.1f}" height="16" rx="2"/>')
    o.append(f'<line class="r" x1="{x0 + lo * scale:.1f}" y1="{y + 10}" x2="{x0 + hi * scale:.1f}" y2="{y + 10}"/>')
    f = "{:.1f}" if hi < 10 else "{:.0f}"
    at = x0 + max(2, med * scale, hi * scale) + 6
    n = (lambda v: f.format(v).replace(".", ",")) if fr else f.format
    o.append(f'<text x="{at:.1f}" y="{y + 14}">{n(med)} ms [{n(lo)}, {n(hi)}]</text>')
    y += line
o.append(f'<text class="s" x="16" y="{y + 24}">{T["foot"]}</text>')
o.append('</svg>')
open(sys.argv[2], "w").write("\n".join(o) + "\n")
