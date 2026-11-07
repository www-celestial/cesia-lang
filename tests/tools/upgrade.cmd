# cesia upgrade against releases in a temporary folder (CESIA_RELEASES), on a copy of the binary: nothing changes until the
# download is checked and the new binary answers.
top=$(mktemp -d)
trap 'rm -rf "$top"' EXIT
case "$(uname -s)" in Darwin) os=macos ;; *) os=linux ;; esac
case "$(uname -m)" in amd64 | x86_64) arch=x86_64 ;; aarch64 | arm64) arch=arm64 ;; *) arch=$(uname -m) ;; esac
archive="cesia-$os-$arch.tar.gz"
mkdir -p "$top/inst/bin" "$top/inst/lib" "$top/new/bin" "$top/new/lib"
cp "$root/_build/default/src/bin/main.exe" "$top/inst/bin/cesia"
printf 'the old lib\n' > "$top/inst/lib/old.txt"
mkdir -p "$top/inst/lib/licenses" && printf 'Cesia\n' > "$top/inst/lib/licenses/Cesia.txt"
printf '#!/bin/sh\necho "cesia 99.0.0"\n' > "$top/new/bin/cesia"
chmod +x "$top/new/bin/cesia"
printf 'the new lib\n' > "$top/new/lib/new.txt"
# release FOLDER FILE TAG NAME FINGERPRINT ASSET: a release as GitHub's API gives it.
release() {
  mkdir -p "$top/$1"
  cp "$top/rel/$archive" "$top/$1/" 2> /dev/null
  printf '%s\n' "$5" > "$top/$1/$archive.blake2"
  printf '{"tag_name": "%s", "name": "%s", "body": "New\\n- feat: something new", "assets": [{"name": "%s", "browser_download_url": "file://%s"}, {"name": "%s.blake2", "browser_download_url": "file://%s"}]}\n' \
    "$3" "$4" "$6" "$top/$1/$archive" "$6" "$top/$1/$archive.blake2" > "$top/$1/$2.json"
}
mkdir -p "$top/rel"
(cd "$top/new" && tar -czf "$top/rel/$archive" bin lib)
good=$(cesia run --allow read fingerprint.ce "$top/rel/$archive")
release rel latest v99.0.0 "cesia 99.0.0" "$good" "$archive"
release rel nightly nightly "cesia 99.1.0-nightly+abc1234" "$good" "$archive"
release old latest v0.1.0 "cesia 0.1.0" "$good" "$archive"
release bad latest v99.0.0 "cesia 99.0.0" "blake2:0000" "$archive"
release none latest v99.0.0 "cesia 99.0.0" "$good" "cesia-other-system.tar.gz"
same() { cmp -s "$top/inst/bin/cesia" "$root/_build/default/src/bin/main.exe" && echo "the old binary, byte for byte"; }
cesia_copy() { "$top/inst/bin/cesia" "$@"; }
echo "== built from the sources"
cesia_copy upgrade
echo "exit $?"
export CESIA_RELEASES="file://$top/rel"
echo "== a lib/ that isn't Cesia's is never touched"
mkdir -p "$top/other/bin" "$top/other/lib"
cp "$root/_build/default/src/bin/main.exe" "$top/other/bin/cesia"
printf 'kept\n' > "$top/other/lib/keep.txt"
echo y | "$top/other/bin/cesia" upgrade 2>&1 | sed "s|$top|TOP|g"
ls "$top/other/lib"
echo "== n"
echo n | cesia_copy upgrade
same
echo "== nightly"
echo n | cesia_copy upgrade --nightly
echo "== not newer"
CESIA_RELEASES="file://$top/old" cesia_copy upgrade
echo "== a bad fingerprint"
echo y | CESIA_RELEASES="file://$top/bad" cesia_copy upgrade 2>&1 | sed "s/$archive/ARCHIVE/"
same
echo "== no archive for this system"
echo y | CESIA_RELEASES="file://$top/none" cesia_copy upgrade 2>&1 | sed "s/$archive/ARCHIVE/"
same
echo "== y"
echo y | cesia_copy upgrade
cesia_copy version
cd "$top/inst" && ls -A . bin lib
