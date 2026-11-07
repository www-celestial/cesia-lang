dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp link-scope.ce "$dir"
cd "$dir"
mkdir data outside
printf 'in\n' > data/in.txt
printf 'secret\n' > outside/secret.txt
ln -s ../outside data/out
ln -s ../outside/secret.txt data/secret.txt
ln -s ../outside/created.txt data/created.txt
ln -s in.txt data/inner.txt
cesia run $no_spec --allow read=data,write=data link-scope.ce 2> /dev/null
echo "exit $?"
echo "== outside holds"
ls outside
