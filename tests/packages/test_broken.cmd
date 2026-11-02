top=$(mktemp -d)
cp -r tested/. "$top"
cd "$top"
printf -- '-- Broken.\nx = )\n' > shape/util.k
kepler test shape
printf -- '-- Stops when it runs.\ndouble(x) = 2 * x\nFailed = 1 + "a"\n' > shape/util.k
kepler test shape
code=$?
cd /
rm -rf "$top"
(exit $code)
