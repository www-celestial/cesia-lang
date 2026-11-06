# The lib/ of a release, beside its bin/, is where c.Open looks first, found from the binary with its links followed; a lib/
# of the current folder is never read, nor a lib/ beside a bin/ without the licenses/Cesia.txt of a release.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
mkdir -p "$top/release/bin" "$top/release/lib/licenses" "$top/links" "$top/here/lib" "$top/plain/bin" "$top/plain/lib"
cp "$root/_build/default/src/bin/main.exe" "$top/release/bin/cesia"
cp "$root/_build/default/tests/c/libfixture.so" "$top/release/lib/libbeside.so"
printf 'Cesia\n' > "$top/release/lib/licenses/Cesia.txt"
cp "$root/_build/default/src/bin/main.exe" "$top/plain/bin/cesia"
cp "$root/_build/default/tests/c/libfixture.so" "$top/plain/lib/libbeside.so"
cp "$root/_build/default/tests/c/libfixture.so" "$top/here/lib/libhere.so"
ln -s "$top/release/bin/cesia" "$top/links/cesia"
printf 'use std/c\nPrint(Args[1], IsOk(c.Open(Args[1])))\n' > "$top/open.ce"
cd "$top/here"
"$top/release/bin/cesia" run $no_spec --allow ffi=beside ../open.ce beside
"$top/links/cesia" run $no_spec --allow ffi=beside ../open.ce beside
"$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=beside ../open.ce beside
"$top/release/bin/cesia" run $no_spec --allow ffi=here ../open.ce here
"$top/plain/bin/cesia" run $no_spec --allow ffi=beside ../open.ce beside
