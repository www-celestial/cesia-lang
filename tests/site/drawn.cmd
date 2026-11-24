# The images that the blocks of a book draw show under them: each .svg file that a block names between quotes and that its
# run wrote, copied into images/ of the site; the French page shows the English one's. A path, or a file that files/ held,
# is no image of the block. Only a drawing is shown: an image with a script, a link, a file it would load or an element a
# drawing has no use for stops the build, so that nothing in the site runs, even an image opened alone.
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME="$t/cache"
f='```'
here=$PWD
# A block drawn on the English page and the same on the French one, as a translated page holds the same blocks.
draw() {
  for page in docs/book/first.md docs/fr/book/first.md; do
    printf '%s\n' "" "${f}cesia allow=read,write" "use std/plot" "use std/sys" "use std/result" "$@" "$f" >> "$page"
  done
}
fresh() {
  rm -rf "$t/proj" "$t/cache"
  cp -r "$here/proj" "$t/"
  cd "$t/proj" || exit 99
}
fresh
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="2"><rect width="4" height="2"/></svg>' > docs/book/files/kept.svg
draw 'plot.Save(plot.Of([plot.Line([1, 2, 3], [2, 1, 3])]), "up.svg") -->' \
  'plot.Save(plot.Frames([plot.Line([1, 2], [1, k]) for k in [1, 2]]), "moving.svg") -->' \
  'sys.Mkdir("sub") then result.IsOk() -->' \
  'plot.Save(plot.Line([1, 2], [1, 2]), "sub/deep.svg") -->' \
  'sys.Read("kept.svg") then result.IsOk() -->' \
  'sys.Write("drawn.txt", "up.svg") then result.IsOk() -->'
cesia doc --site > /dev/null
echo "built: $?"
echo "== under the block, at its size, with its title or what it is for those who can't see it"
grep -o '<figure class="drawn">.*</figure>' site/first.html
echo "== the French page, from its own folder"
grep -o '<figure class="drawn">.*</figure>' site/fr/first.html
echo "== the files: those plot.Save wrote"
ls site/images/first
head -c 52 site/images/first/up.svg; echo
echo "== a build from the cache, which runs nothing again, still writes them"
rm -r .cesia/site
cesia doc --site > /dev/null
if [ -e .cesia/site ]; then echo "a page ran again"; else echo "nothing ran again"; fi
ls site/images/first
echo "== a page with no drawing any more: its images go"
fresh
cesia doc --site > /dev/null
ls site | grep -c images
# Each one alone, in a fresh copy of the project, written from a file of files/ so that no quote of the shell is in the way.
bad() {  # what is wrong, then the text of the image
  echo "== $1"
  fresh
  printf '%s\n' "$2" > docs/book/files/bad.txt
  draw 'sys.Write("bad.svg", result.Unwrap(sys.Read("bad.txt"))) then result.IsOk() -->'
  cesia doc --site 2>&1 | sed "s#$t#TMP#g"
  echo "exit ${PIPESTATUS[0]}"
}
bad "a script" '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>'
bad "an attribute that runs code" '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><rect width="1" height="1"/></svg>'
bad "a link" '<svg xmlns="http://www.w3.org/2000/svg"><a href="https://example.com"><rect width="1" height="1"/></a></svg>'
bad "an element a drawing has no use for" '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject width="9" height="9"></foreignObject></svg>'
bad "a file it would load" '<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1" fill="url(https://example.com/a.svg#p)"/></svg>'
bad "a style that imports" '<svg xmlns="http://www.w3.org/2000/svg"><style>@import "https://example.com/a.css";</style></svg>'
bad "an entity declared" '<!DOCTYPE svg [<!ENTITY e "x">]><svg xmlns="http://www.w3.org/2000/svg"><text>&e;</text></svg>'
bad "a < that opens nothing" '<svg xmlns="http://www.w3.org/2000/svg"><text>1 < 2</text></svg>'
