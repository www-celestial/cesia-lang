top=$(mktemp -d)
cp -r tested/. "$top"
cd "$top"
cesia test shape
cesia test shape/rect.test.ce
cesia test .
code=$?
cd /
rm -rf "$top"
(exit $code)
