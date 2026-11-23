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
# A tree 200 folders deep, made by one mkdir.
deep=out/deep
for ((i = 0; i < 200; i++)); do deep=$deep/d; done
mkdir -p "$deep" && printf 'bottom\n' > "$deep/f.txt"
mkdir -p out/locked/inner
printf 'l\n' > out/locked/inner/l.txt
chmod a-w out/locked/inner
cesia run $no_spec --allow read=out,write=out remove-tree.ce "$(pwd -P)" 2> /dev/null
echo "== outside holds"
find outside | LC_ALL=C sort
