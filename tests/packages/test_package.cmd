top=$(mktemp -d)
cp -r tested/. "$top"
cd "$top"
kepler test shape
kepler test shape/rect.test.k
kepler test .
code=$?
cd /
rm -rf "$top"
(exit $code)
