# path.Abs from a folder of its own: with the read permission on photos only, then on everything.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp abs.ce "$dir"
cd "$dir"
mkdir photos
here=$(pwd -P)
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read abs.ce "$here" all
"$root/_build/default/src/bin/main.exe" run $no_spec --allow read=photos abs.ce "$here" photos
