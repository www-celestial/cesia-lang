# Each mistake of a book fails the build and names its place.
t=$(mktemp -d)
export XDG_CACHE_HOME="$t/cache"
f='```'
add() { printf '%s\n' "$@" >> docs/book/first.md; }
try() {  # what goes wrong, then the command that puts it in a copy of the project
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
try "a name in brackets that leads nowhere" 'add "" "See [NoSuchName]."'
try "a toml block that doesn't parse" 'add "" "${f}toml" "[project" "$f"'
try "a page that book/index.md doesn't link" 'echo "# Extra" > docs/book/extra.md'
try "a link to a page that isn't there" 'echo "Then [more](gone.md)." >> docs/book/index.md'
try "two pages whose names differ only in case" 'cp docs/book/files.md docs/book/Files.md && echo "And [again](Files.md)." >> docs/book/index.md'
try "a book without its index.md" 'rm docs/book/index.md'
rm -rf "$t"
