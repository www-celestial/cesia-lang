# An engine that an earlier build of Cesia made for this machine still loads: its Cesia_v1 is this one. tools/test.sh runs
# this folder only when it holds an engine for the tag of this Cesia: an engine is made for one system and one compiler.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
cp -R echo/. "$top"
tag=$(cesia run ../tag.ce)
mkdir "$top/native"
cat "echo-$tag.cmxs" > "$top/native/echo-$tag.cmxs"
cd "$top"
cesia run $no_spec --allow native=echo src/main.ce
