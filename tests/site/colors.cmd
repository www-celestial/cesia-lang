# Every language a book shows, in the roles of Cesia's code: keywords, called names, texts, numbers, comments and fields,
# with the cases that trap a reader, a ' of a lifetime or a type, a # in an address, a // in a text, nested comments, raw
# texts, holes of code in texts; a language the site doesn't know read the generic way; text and output as they are. A
# block that names no language is shown as it is and named, and the build goes on. The HTML of each block holds every
# byte of it, in its order.
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export XDG_CACHE_HOME="$t/cache"
cp -R colors "$t/"
cd "$t/colors" || exit 1
cesia doc --site 2>&1 > /dev/null
echo "built: $?"
sed -n '/<main/,/<\/main>/p' site/index.html
cesia run --allow read "$root/tests/site/kept.ce" docs/book/index.md site/index.html
