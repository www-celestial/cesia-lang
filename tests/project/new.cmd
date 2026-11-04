dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
cesia new hello
cat hello/cesia.toml hello/src/main.ce
(cd hello && cesia do run)
ls hello/pkg | tr '\n' ' '
echo
(cd hello && cesia pkg && echo "all agree" && printf '\n(** Mine. *)\nMine = 1\n' >> pkg/rope/rope.ce && cesia pkg && cesia pkg update rope && cesia pkg && echo "all agree again" && cesia test $no_spec . && cesia pkg update nope)
echo "exit $?"
cesia new hello
echo "exit $?"
cesia new a/b
echo "exit $?"
cesia new
