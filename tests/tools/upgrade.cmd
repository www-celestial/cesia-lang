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
echo "== a step that fails puts back what was done: the new lib/ in place, the binary can't be moved aside"
mkdir -p "$top/inst/bin/.old-cesia/x"
echo y | cesia_copy upgrade 2>&1 | tail -1 | sed "s|$top|TOP|g"
same
(cd "$top/inst" && ls -A . lib)
rm -r "$top/inst/bin/.old-cesia"
echo "== an address without encryption"
mkdir -p "$top/plain"
printf '{"tag_name": "v99.0.0", "name": "cesia 99.0.0", "body": "", "assets": [{"name": "%s", "browser_download_url": "http://127.0.0.1:9/a"}, {"name": "%s.blake2", "browser_download_url": "http://127.0.0.1:9/b"}]}\n' \
  "$archive" "$archive" > "$top/plain/latest.json"
echo y | CESIA_RELEASES="file://$top/plain" cesia_copy upgrade 2>&1 | tail -1
same
echo "== y"
echo y | cesia_copy upgrade
cesia_copy version
cd "$top/inst" && ls -A . bin lib
echo "== an archive that holds an old-lib/ of its own: lib/ is the new one, and nothing is left"
mkdir -p "$top/inst2/bin" "$top/inst2/lib/licenses" "$top/new2/old-lib" "$top/rel2"
cp "$root/_build/default/src/bin/main.exe" "$top/inst2/bin/cesia"
printf 'Cesia\n' > "$top/inst2/lib/licenses/Cesia.txt"
cp -R "$top/new/bin" "$top/new/lib" "$top/new2/"
printf 'not a lib\n' > "$top/new2/old-lib/x.txt"
(cd "$top/new2" && tar -czf "$top/rel2/$archive" bin lib old-lib)
good2=$(cesia run --allow read "$root/tests/tools/fingerprint.ce" "$top/rel2/$archive")
printf '{"tag_name": "v99.0.0", "name": "cesia 99.0.0", "body": "", "assets": [{"name": "%s", "browser_download_url": "file://%s"}, {"name": "%s.blake2", "browser_download_url": "file://%s"}]}\n' \
  "$archive" "$top/rel2/$archive" "$archive" "$top/rel2/$archive.blake2" > "$top/rel2/latest.json"
printf '%s\n' "$good2" > "$top/rel2/$archive.blake2"
echo y | CESIA_RELEASES="file://$top/rel2" "$top/inst2/bin/cesia" upgrade 2>&1 | tail -1 | sed "s|$top|TOP|g"
cd "$top/inst2" && ls -A . lib
