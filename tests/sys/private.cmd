# sys.Mkdir and sys.Write with private = true: the modes they give, under the usual umask and under a strict one; a
# reader that opened a file before its private write, which reads the old text after it; a link replaced, its target
# left as it was; no temporary file left behind; private needs the write permission, as without.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp private.ce "$dir"
cd "$dir"
made() {
  mkdir -p open
  printf 'old text' > open/reader.txt
  printf 'target' > target.txt
  chmod 644 open/reader.txt target.txt
  ln -s ../target.txt open/link.txt
}
modes() {
  for p in open open/inside open/plain.txt open/was-plain.txt open/reader.txt open/link.txt target.txt keys keys/deep keys/deep/er keys/key.txt; do
    echo "$(ls -ld "$p" | cut -c1-10) $p"
  done
  echo "left behind: $(ls -A open keys | grep -c tmp)"
}
umask 022
made
exec 3< open/reader.txt
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=.,write=. private.ce
echo "the reader opened before: $(cat <&3)"
exec 3<&-
modes
rm -rf open keys target.txt
umask 077
made
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=.,write=. private.ce > /dev/null
modes
rm -rf open keys target.txt
made
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=. private.ce
