dir=$(mktemp -d)
trap 'chmod -R u+w "$dir"; rm -rf "$dir"' EXIT
cp remove-tree.ce "$dir"
cd "$dir"
mkdir -p out/tree/a/b out/tree/c outside/keep
printf 'kept\n' > outside/keep/k.txt
printf 'kept\n' > outside/k.txt
printf 'x\n' > out/tree/a/b/x.txt
printf 'y\n' > out/tree/c/y.txt
printf 'z\n' > out/tree/z.txt
ln -s ../../outside out/tree/a/to-folder
ln -s ../../outside/k.txt out/tree/c/to-file
ln -s ../outside out/link
printf 'f\n' > out/file.txt
(cd out && mkdir deep && cd deep && for _ in $(seq 200); do mkdir d && cd d || exit; done && printf 'bottom\n' > f.txt)
mkdir -p out/locked/inner
printf 'l\n' > out/locked/inner/l.txt
chmod a-w out/locked/inner
cesia run $no_spec --allow read=out,write=out remove-tree.ce "$(pwd -P)" 2> /dev/null
echo "== outside holds"
find outside | sort
