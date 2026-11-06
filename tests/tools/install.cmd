# install.sh against a release in a temporary folder: the archive goes in once its fingerprint is checked, and cesia and ce
# run from the folder of links.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
case "$(uname -s)" in Darwin) os=macos ;; *) os=linux ;; esac
case "$(uname -m)" in amd64 | x86_64) arch=x86_64 ;; aarch64 | arm64) arch=arm64 ;; *) arch=$(uname -m) ;; esac
archive="cesia-$os-$arch.tar.gz"
mkdir -p "$top/out/bin" "$top/out/lib" "$top/rel" "$top/bad"
cp "$root/_build/default/src/bin/main.exe" "$top/out/bin/cesia"
printf 'a library\n' > "$top/out/lib/libsome.so"
tar -czf "$top/rel/$archive" -C "$top/out" bin lib
sum() { if command -v sha256sum > /dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
sum "$top/rel/$archive" > "$top/rel/$archive.sha256"
cp "$top/rel/$archive" "$top/bad/"
echo 0000 > "$top/bad/$archive.sha256"
export CESIA_HOME="$top/home" CESIA_BIN="$top/links"
clean() { sed -e "s|$top|TOP|g" -e "s/$archive/ARCHIVE/"; }
CESIA_RELEASES="file://$top/bad" sh "$root/install.sh" 2>&1 | clean
ls "$top" | tr '\n' ' '
echo
CESIA_RELEASES="file://$top/rel" sh "$root/install.sh" 2>&1 | grep -v "to your PATH" | clean
"$top/links/ce" version
cd "$top/home" && ls -A . bin lib
