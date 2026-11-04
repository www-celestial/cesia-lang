dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
cesia new hello
cat hello/cesia.toml hello/.gitignore hello/src/main.ce
(cd hello && cesia do run)
ls hello/pkg | tr '\n' ' '
echo
cd hello
# Each file of pkg/ has one line in cesia.lock, with its fingerprint.
for f in $(find pkg -name '*.ce' | sort); do grep -c "\"$f blake2:[0-9a-f]\{64\}\"" cesia.lock; done | sort | uniq -c | tr -s ' '
cesia pkg | grep -v "as installed$"
echo "all as installed"
printf '\n(** Mine. *)\nMine = 1\n' >> pkg/rope/rope.ce
cesia pkg | grep -v "as installed$"
cesia pkg install
cesia pkg | grep -v "as installed$"
echo "all as installed again"
cesia pkg install
echo "nothing to install: $?"
# After a clone: git keeps neither pkg/ nor deps/.
rm -r pkg
cesia pkg | grep -v "as installed$"
cesia pkg install
cesia pkg | grep -v "as installed$"
cesia test $no_spec .
cesia pkg nope
echo "exit $?"
cd ..
cesia pkg
echo "exit $?"
cesia new hello
echo "exit $?"
cesia new a/b
echo "exit $?"
cesia new
