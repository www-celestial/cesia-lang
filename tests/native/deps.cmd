# A program uses a native package of deps/: it runs the engine with native= and the label of the dependency, once the
# engine is as cesia.lock says.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
dep="$top/deps/someone/echo"
mkdir -p "$top/src" "$dep/native"
cp -R echo/. "$dep"
tag=$(cesia run tag.ce)
cat "$root/_build/default/tests/native/echo.cmxs" > "$dep/native/echo-$tag.cmxs"
printf '[project]\nname = "app"\n\n[deps.echoes]\nfrom = "github.com/someone/echo"\nversion = "v0.1.0"\ntake = ["cesia/echo"]\n' > "$top/cesia.toml"
printf 'use deps/someone/echo/cesia/echo\nuse std/io\nio.Print(echo.Echo4(1, 2.5, "from deps", false))\nio.Print(echo.Reverse([1, 2]))\n' > "$top/src/main.ce"
cd "$top"
cesia run --allow read,write "$root/tests/native/lock.ce"
run() { cesia run $no_spec "$@" src/main.ce 2>&1 | sed "s/$tag/TAG/g"; }
run
run --allow native=echoes
printf 'x' >> "deps/someone/echo/native/echo-$tag.cmxs"
run --allow native=echoes
rm "deps/someone/echo/native/echo-$tag.cmxs"
run --allow native=echoes
