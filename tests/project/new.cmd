dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
cesia new hello
cat hello/cesia.toml hello/src/main.ce
(cd hello && cesia do run)
cesia new hello
echo "exit $?"
cesia new a/b
echo "exit $?"
cesia new
