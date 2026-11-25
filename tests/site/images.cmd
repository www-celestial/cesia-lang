# The images of a book, written ![what it shows](images/name.png) from the page's own folder, as GitHub shows them: the
# files of docs/BOOK/images/ are copied into the site, those of the home book at its root, those of another book in its
# folder, and each page leads to them from its own place; a French page shows the English one's from its folder. Each
# mistake stops the build and names its place: an image that isn't there, from elsewhere, outside images/ or with no
# text; a file of images/ that is no image a browser shows, an SVG that is no drawing, a link.
t=$(mktemp -d)
port=$(cesia run --allow net=own "$root/tests/free-port.ce")
trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME="$t/cache"
here=$PWD
fresh() {
  rm -rf "$t/proj"
  cp -r "$here/proj" "$t/"
  cd "$t/proj" || exit 99
  # The server of files.md listens on a port the system gave free: 18751 there stands for it, and another test could
  # hold it. Not sed -i, which macOS reads otherwise.
  sed "s/18751/$port/g" docs/book/files.md > "$t/files.md" && mv "$t/files.md" docs/book/files.md
  mkdir -p docs/book/images/parts docs/guides/images
  # A PNG of one pixel, and a drawing made by hand with the shapes of SVG.
  echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' | base64 -d > docs/book/images/dot.png
  printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><line x1="0" y1="0" x2="40" y2="20" stroke="#000"/><polygon points="0,20 10,10 20,20"/><ellipse cx="30" cy="10" rx="5" ry="3"/><text x="2" y="18">a<tspan>b</tspan></text></svg>' > docs/book/images/parts/box.svg
  cp docs/book/images/dot.png docs/guides/images/g.png
}
add() {  # a file, then its lines
  f=$1
  shift
  printf '%s\n' "" "$@" >> "$f"
}
fresh
add docs/book/first.md '![A dot](images/dot.png) and ![A box, *drawn* by hand](images/parts/box.svg "The box")'
add docs/fr/book/first.md '![Un point](../../book/images/dot.png) et ![Une boîte](../../book/images/parts/box.svg "La boîte")'
add docs/guides/index.md '![A guide](images/g.png)'
add README.md '![The dot](docs/book/images/dot.png)'
cesia doc --site > /dev/null
echo "built: $?"
echo "== each page leads to the image from its own place"
# One file at a time, in this order: a grep may read several in any order.
for f in site/first.html site/fr/first.html site/guides/index.html site/readme.html; do
  grep -o '<img [^>]*>' "$f" | sed "s#^#$f: #"
done
echo "== the files, as they were, byte for byte"
ls site/images site/images/parts site/guides/images
cmp docs/book/images/dot.png site/images/dot.png && cmp docs/book/images/parts/box.svg site/images/parts/box.svg && echo same
echo "== a build that keeps the pages still writes them"
cesia doc --site > /dev/null
ls site/images
# Each one alone, in a fresh copy of the project.
try() {  # what goes wrong, then the command that puts it in the copy
  echo "== $1"
  fresh
  eval "$2"
  cesia doc --site 2>&1 | sed "s#$t#TMP#g; s#^[0-9]* files: #N files: #"
  echo "exit ${PIPESTATUS[0]}"
}
try "an image that isn't there" 'add docs/book/first.md "![Gone](images/gone.png)"'
try "an image with no text" 'add docs/book/first.md "![](images/dot.png)"'
try "an image from elsewhere" 'add docs/book/first.md "![Far](https://example.com/a.png)"'
try "an image outside images/" 'add docs/book/first.md "![Notes](files/notes.txt)"'
try "a French image that leads nowhere from its folder" 'add docs/fr/book/first.md "![Un point](images/dot.png)"'
try "a file of images/ that is no image a browser shows" 'printf x > docs/book/images/old.bmp'
try "an SVG of images/ with a script" 'printf "%s" "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>" > docs/book/images/bad.svg'
try "a link in images/" 'ln -s ../files/notes.txt docs/book/images/leak.png'
