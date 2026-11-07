# The author's own project: the files of its native package see the natives of the engine in native/, built for this
# Cesia, which a program runs with native= and the project's name. cesia check runs no engine, and needs no permission.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
cp -R echo/. "$top"
tag=$(cesia run tag.ce)
mkdir "$top/native"
cat "$root/_build/default/tests/native/echo.cmxs" > "$top/native/echo-$tag.cmxs"
cd "$top"
cesia check cesia/echo/echo.ce src/main.ce
echo "check: $?"
cesia run $no_spec src/main.ce
cesia run $no_spec --allow read=.,native=echo src/main.ce
cesia do main 2>&1 | tail -1
