# sys.Mkdir and sys.Write with private = true: the modes they give, under the usual umask and under a strict one;
# private needs the write permission, as without.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp private.ce "$dir"
cd "$dir"
modes() {
  for p in open open/inside open/plain.txt open/was-plain.txt keys keys/deep keys/deep/er keys/key.txt; do
    echo "$(ls -ld "$p" | cut -c1-10) $p"
  done
}
umask 022
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=.,write=. private.ce
modes
rm -rf open keys
umask 077
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=.,write=. private.ce > /dev/null
modes
rm -rf open keys
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=. private.ce
