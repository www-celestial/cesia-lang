# Each mistake of a book fails the build and names its place.
t=$(mktemp -d)
export XDG_CACHE_HOME="$t/cache"
f='```'
add() { printf '%s\n' "$@" >> docs/book/first.md; }
try() {  # what goes wrong, then the command that puts it in a copy of the project, without its French
  french "$1" "rm -r docs/fr README.fr.md && $2"
}
french() {  # the same, with its French pages
  echo "== $1"
  rm -rf "$t/proj"
  cp -r proj "$t/"
  # book.cmd serves on 18751 at the same time. Not sed -i, which macOS reads otherwise.
  sed 's/18751/18752/g' "$t/proj/docs/book/files.md" > "$t/files.md" && mv "$t/files.md" "$t/proj/docs/book/files.md"
  (cd "$t/proj" && eval "$2" && cesia doc --site; echo "exit $?") 2>&1 | sed "s#$t#TMP#g"
}
try "a wrong -->" 'add "" "${f}cesia" "1 + 1 --> 3" "$f"'
try "a block that stops" 'add "" "${f}cesia" "math.Div(1, 0)" "$f"'
try "a block marked fails that ends well" 'add "" "${f}cesia fails" "1 + 1" "$f"'
try "a wrong --> in a block marked fails, before it stops" 'add "" "${f}cesia fails" "1 + 1 --> 3" "math.Div(1, 0)" "$f"'
try "a --> at the end of a call written on several lines" 'add "" "${f}cesia" "list.Max(1," "  2) -->" "$f"'
try "a norun block with an unknown name" 'add "" "${f}cesia norun" "NoSuchName(1)" "$f"'
try "a word cesia blocks don't have" 'add "" "${f}cesia quiet" "1" "$f"'
try "--> error in a book" 'add "" "${f}cesia" "math.Div(1, 0) --> error" "$f"'
try "tabs out of order, and one with a word after its language" 'add "" "${f}cesia" "1" "$f" "${f}r" "1" "$f" "${f}python x" "1" "$f"'
try "tabs on a block that fails" 'add "" "${f}cesia fails" "math.Div(1, 0)" "$f" "${f}python" "1 // 0" "$f"'
try "a name in brackets that leads nowhere" 'add "" "See [NoSuchName]."'
try "a toml block that doesn't parse" 'add "" "${f}toml" "[project" "$f"'
try "a page that book/index.md doesn't link" 'echo "# Extra" > docs/book/extra.md'
try "a link to a page that isn't there" 'echo "Then [more](gone.md)." >> docs/book/index.md'
# A system whose files ignore case, as macOS's, can't hold the two pages, which is why the check exists: there the case
# is skipped, and its lines are written as they are where it runs.
touch "$t/case" && if [ -e "$t/CASE" ]; then
  printf '%s\n' "== two pages whose names differ only in case" "files.html and Files.html differ only in case." "exit 1"
else
  try "two pages whose names differ only in case" 'cp docs/book/files.md docs/book/Files.md && echo "And [again](Files.md)." >> docs/book/index.md'
fi
try "a book without its index.md" 'rm docs/book/index.md'
try "a formula with a command it doesn't know" 'add "" "So \$\\foo + 1\$."'
try "a formula with a character TeX writes otherwise" 'add "" "So \$x ≤ y\$ and \$x^\$."'
try "a formula whose group isn't closed" 'add "" "" "\$\$" "\\frac{1}{2" "\$\$"'
try "a color that isn't one" 'printf "%s\n" "[site]" "color = \"blue\"" >> cesia.toml'
try "a README that links to a file which is no page" 'echo "See [the license](LICENSE)." >> README.md'
french "a French page that drifts from its English one" 'sed "s/^x \\* 2 --> 10$/x * 2 --> 11/; s/^# Premiers pas$/## Premiers pas/; s/(first.md)/(files.md)/" docs/fr/book/first.md > f && mv f docs/fr/book/first.md && sed "s/(first.md)/(files.md)/" docs/fr/book/index.md > f && mv f docs/fr/book/index.md'
french "a French page with no English one" 'echo "# En plus" > docs/fr/book/extra.md'
french "a French link to a heading that isn't there" 'sed "s/#premiers-pas/#first-steps/" README.fr.md > f && mv f README.fr.md'
rm -rf "$t"
