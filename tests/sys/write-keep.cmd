# sys.Write with a mode and a group, set on the file it opens before the text is in; the save of an editor, a new file
# renamed over the old one, keeps both; sys.Copy with new = true makes only a new file; sys.Stat gives the owner and the
# group. Run with read=out and write=out, by a person who is not root.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp write-keep.ce "$dir"
cd "$dir"
umask 022
mkdir out
printf 'old\n' > out/doc.txt
chmod 640 out/doc.txt
printf 'elsewhere\n' > elsewhere.txt
ln -s ../elsewhere.txt out/planted
ln -s ../nothing.txt out/dangling
# A group the person is not in.
other=4242
while id -G | tr ' ' '\n' | grep -qx "$other"; do other=$((other + 1)); done
cesia run $no_spec --allow read=out,write=out write-keep.ce $(ls -ln out/doc.txt | awk '{ print $3, $4 }') "$other" 2> /dev/null
echo "exit $?"
echo "== modes"
ls -l out | awk 'NR > 1 { print substr($1, 1, 10), $NF }'
echo "== out of the folder: $(cat elsewhere.txt), $(ls nothing.txt 2> /dev/null | wc -l | tr -d ' ') new file"
