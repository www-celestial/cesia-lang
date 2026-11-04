dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp fs-extra.ce "$dir"
cd "$dir"
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=.,write=. fs-extra.ce
