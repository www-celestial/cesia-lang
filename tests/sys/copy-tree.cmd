# sys.CopyTree, run with read=src, read=out and write=out: a folder and all it holds, its links made again, never
# followed, its modes and times kept; a folder there takes it in, its files and links replaced; what it can't copy, named.
dir=$(mktemp -d)
trap 'chmod -R u+w "$dir"; rm -rf "$dir"' EXIT
cp copy-tree.ce "$dir"
cd "$dir"
mkdir -p src/tree/a/b src/tree/c out/there/a outside
printf 'kept\n' > outside/k.txt
printf 'x\n' > src/tree/a/b/x.txt
printf 'y\n' > src/tree/c/y.txt
printf '#!/bin/sh\n' > src/tree/run.sh
chmod 750 src/tree/run.sh
chmod 750 src/tree/c
ln -s ../../../outside src/tree/a/to-folder
ln -s b/x.txt src/tree/a/to-x
touch -t 200102030405.06 src/tree/c/y.txt src/tree/c
printf 'old\n' > out/there/a/x.txt
ln -s ../../outside/k.txt out/there/run.sh
ln -s ../outside out/link
# A tree 100 folders deep, made by one mkdir.
deep=src/deep
for ((i = 0; i < 100; i++)); do deep=$deep/d; done
mkdir -p "$deep" && printf 'bottom\n' > "$deep/f.txt"
mkdir src/pipe && mkfifo src/pipe/fifo
cesia run $no_spec --allow read=src,read=out,write=out copy-tree.ce 2> /dev/null
echo "== the copy"
mode() { ls -ld "$1" | cut -c 2-10; }
show() {
  (cd "$1" && find . -print | LC_ALL=C sort | while read -r p; do
    if [ -L "$p" ]; then echo "$p -> $(readlink "$p")"; elif [ -d "$p" ]; then echo "$p/ $(mode "$p")"; else echo "$p $(mode "$p") $(cat "$p")"; fi
  done)
}
show out/tree
echo "== times: $(ls -ld --time-style=+%s src/tree/c/y.txt src/tree/c out/tree/c/y.txt out/tree/c | awk '{ print $6 }' | sort -u | wc -l | tr -d ' ') for the four"
echo "== a folder there"
show out/there
echo "== deep: $(find out/deep -name f.txt | wc -l | tr -d ' ')"
echo "== outside holds"
find outside | LC_ALL=C sort
cat outside/k.txt
