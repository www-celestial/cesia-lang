# An engine loads only if made for this Cesia, checked before any of its code runs: one that reaches inside Cesia past
# Cesia_v1, or brings a module the program holds already, is refused, and its natives must be those of its cesia.toml.
# A [native] that names a public native, or a field it doesn't know, stops the first use.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
cp -R echo/. "$top"
tag=$(cesia run tag.ce)
built="$root/_build/default/tests/native"
mkdir "$top/native"
cd "$top"
run() { cesia run $no_spec --allow read=.,native=echo src/main.ce 2>&1 | head -1 | sed "s/$tag/TAG/g"; }
run
cat "$built/echo.cmxs" > native/echo-1-ocaml4.14.0-linux-x86_64.cmxs
run
rm native/echo-1-ocaml4.14.0-linux-x86_64.cmxs
cat "$built/inside.cmxs" > "native/echo-$tag.cmxs"
run
cat "$built/taken.cmxs" > "native/echo-$tag.cmxs"
run
cat "$built/lacks.cmxs" > "native/echo-$tag.cmxs"
run
cat "$built/echo.cmxs" > "native/echo-$tag.cmxs"
toml() { printf '[project]\nname = "echo"\nsrc = ["cesia", "src"]\n\n[native]\npackage = "cesia/echo"\n%s\n' "$1" > cesia.toml; }
toml 'natives = ["echo4", "kindOf", "reverse", "fields", "field", "thing", "number", "boom", "refuse", "read", "later", "same", "soon"]'
run
toml 'natives = ["Len"]'
run
toml 'natives = ["echo4"]
engine = "echo.cmxs"'
run
toml 'natives = "echo4"'
run
toml ''
run
