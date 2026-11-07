dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/a" "$dir/b"
printf '#!/bin/sh\necho "mine, in $(basename "$(pwd)")"\n' > "$dir/a/build.sh"
printf '#!/bin/sh\necho other\n' > "$dir/b/build.sh"
chmod +x "$dir/a/build.sh" "$dir/b/build.sh"
cp run-path.ce "$dir/a"
cd "$dir/a"
cesia run $no_spec --allow exec=./build.sh run-path.ce
