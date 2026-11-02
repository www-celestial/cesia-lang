dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp fs-extra.k "$dir"
cd "$dir"
"$root/_build/default/bin/main.exe" run $no_spec --allow read=.,write=. fs-extra.k
