# sys.Copy opens its source without waiting, then sees what it is: a pipe, a link to one, or a device is an Err at once,
# where a pipe held the program until someone wrote into it; a link to a file still copies the file.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp copy-fifo.ce "$dir"
cd "$dir"
mkfifo pipe
ln -s pipe to-pipe
printf 'x\n' > file.txt
ln -s file.txt to-file
# timeout runs a program, not the shell function cesia: the binary of this tree.
timeout 20 "$root/_build/default/src/bin/main.exe" run $no_spec --allow read=.,read=/dev/null,write=. copy-fifo.ce 2> /dev/null
echo "exit $?"
echo "made: $(ls | LC_ALL=C sort | tr '\n' ' ')"
[ -L copy-of-file ] && echo "the copy is a link" || echo "the copy is a file: $(cat copy-of-file)"
