# cesia fmt on copies of its files: --check names a file out of the style and fails, fmt writes it in the style and leaves
# a file in it as it is, a file that doesn't read stays and is named, a file with \r\n keeps them, and the formatted
# file runs as before.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
cp messy.ce clean.ce broken.ce crlf.ce "$top/"
cd "$top"
cesia run messy.ce
cesia fmt --check messy.ce clean.ce
echo "check: $?"
cesia fmt messy.ce clean.ce broken.ce crlf.ce
echo "fmt: $?"
cat messy.ce
od -c crlf.ce | sed 's/  */ /g'
cesia fmt --check messy.ce clean.ce crlf.ce
echo "check again: $?"
cesia run messy.ce
cesia fmt
echo "no path: $?"
cesia fmt --nope
echo "unknown option: $?"
