dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp snapshot.test.ce "$dir/"
cd "$dir"
echo "== new snapshots fail"
cesia test $no_spec snapshot.test.ce
echo "== --update accepts them"
cesia test $no_spec --update snapshot.test.ce
cat snapshot.test.snap
echo "== then they pass"
cesia test $no_spec snapshot.test.ce
echo "== a change shows its lines"
sed -i.bak 's/Total: 3/Total: 4/' snapshot.test.ce
cesia test $no_spec snapshot.test.ce
echo "== one test updated, the others kept"
cesia test $no_spec --update snapshot.test.ce:isPage
grep -c "^== is" snapshot.test.snap
echo "== a test gone takes its block with it"
sed -i.bak '/^isOdd/d' snapshot.test.ce
cesia test $no_spec --update snapshot.test.ce
grep "^== is" snapshot.test.snap
