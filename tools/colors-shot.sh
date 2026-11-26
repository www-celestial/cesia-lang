#!/usr/bin/env bash
# The two images of the chapter Tests on the colors of a site, in docs/book/images/, which the English and the French pages
# show: colors-languages.png, blocks of Java, SQL, JSON and a diff as cesia doc --site colors them, light, two by two;
# and colors-warning.png, the warning of a block that names no language as a terminal shows it. Each is made from a build
# of a tiny book by the cesia of _build, drawn by a Chrome without a window, then cut to what it shows and kept in 256
# colors. Needs a Chrome, which CHROME names, else chromium, google-chrome or chrome-headless-shell in the PATH, and
# ImageMagick.
#   tools/colors-shot.sh
set -eu
cd "$(dirname "$0")/.."
root=$PWD
cesia="$root/_build/default/src/bin/main.exe"
chrome=${CHROME:-$(command -v chromium || command -v google-chrome || command -v chrome-headless-shell || true)}
[ -n "$chrome" ] || { echo "colors-shot: no Chrome: name one with CHROME=..." >&2; exit 1; }
command -v magick > /dev/null || { echo "colors-shot: no ImageMagick" >&2; exit 1; }
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
f='```'
mkdir -p "$t/shop/docs/book"
printf '[project]\nname = "shop"\n' > "$t/shop/cesia.toml"
cat > "$t/shop/docs/book/index.md" << EOF
# Shop

${f}java
// An invoice, paid once
@Entity
public class Invoice {
    private long total = 1_250L;
    public String label() { return "Invoice #" + id; }
}
$f

${f}sql
-- The unpaid invoices of a client
SELECT i.number, i.total FROM invoice i
WHERE i.client = \$1 AND i.status = 'unpaid'
ORDER BY i.due DESC LIMIT 10;
$f

${f}json
{"number": 42, "total": 12.5,
 "paid": false, "client": {"name": "Ana"},
 "lines": ["tea", "bread"]}
$f

${f}diff
@@ -1,3 +1,3 @@
 total = 10
-paid = false
+paid = true
$f

$f
x = 1
$f
EOF
(cd "$t/shop" && XDG_CACHE_HOME="$t/cache" "$cesia" doc --site > "$t/out.txt" 2> "$t/err.txt")
# The blocks of the page, each <pre> on its lines, side by side in the site's own CSS.
awk '/<pre><code class="language-/ { on = 1 } on { print } /<\/code><\/pre>/ { on = 0 }' "$t/shop/site/index.html" |
  awk 'BEGIN { print "<!doctype html><html data-theme=\"light\"><head><meta charset=\"utf-8\"><link rel=\"stylesheet\" href=\"site.css\">"
    print "<style>body { margin: 0; background: #fff; } .grid { display: grid; grid-template-columns: 430px 430px; gap: 10px;"
    print "padding: 16px; width: max-content; } pre { margin: 0; font-size: 13px; }</style></head><body><div class=\"grid\">" }
    /<pre>/ { printf "<div>" } { print } /<\/pre>/ { print "</div>" } END { print "</div></body></html>" }' > "$t/shop/site/grid.html"
# The terminal: the command, what it wrote on its error then its output, with the folder of the book as /home/ana/shop.
{
  printf '<!doctype html><html><head><meta charset="utf-8"><style>body { margin: 0; background: #fff; } pre { margin: 16px;'
  printf ' padding: 12px 16px; width: 88ch; white-space: pre-wrap; background: #1e1f22; color: #dadde2; border-radius: 6px;'
  printf ' font: 13px/1.45 ui-monospace, "DejaVu Sans Mono", Menlo, Consolas, monospace; } b { color: #6aab73; font-weight: normal; }'
  printf '</style></head><body><pre><b>ana@box:~/shop$</b> cesia doc --site\n'
  sed -e "s#$t/shop#/home/ana/shop#g" -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$t/err.txt" "$t/out.txt"
  printf '</pre></body></html>\n'
} > "$t/shop/site/terminal.html"
shot() {  # page, image
  "$chrome" --headless --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$t/profile" --force-device-scale-factor=1 \
    --window-size=1000,800 --screenshot="$t/shot.png" "file://$t/shop/site/$1" > /dev/null 2>&1
  magick "$t/shot.png" -trim +repage -bordercolor white -border 12 -strip PNG8:"$root/docs/book/images/$2"
  echo "docs/book/images/$2: $(magick identify -format '%wx%h' "$root/docs/book/images/$2"), $(wc -c < "$root/docs/book/images/$2") bytes"
}
shot grid.html colors-languages.png
shot terminal.html colors-warning.png
