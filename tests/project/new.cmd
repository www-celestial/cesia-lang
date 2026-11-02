dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
kepler new hello
cat hello/kepler.toml hello/main.k
(cd hello && kepler do run)
kepler new hello
echo "exit $?"
kepler new a/b
echo "exit $?"
kepler new
