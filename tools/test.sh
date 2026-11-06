#!/usr/bin/env bash
# The full suite, on both paths.
set -eu
cd "$(dirname "$0")/.."
dune build 2>&1 | head -60
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
cesia=_build/default/src/bin/main.exe

# Cesia's own site, beside the rest: a text of the docs with a [Name] that leads nowhere, or a block of the book that gives
# another value, fails here. Its servers listen on ports that no test uses.
site=$(mktemp -d)
trap 'rm -rf "$site" "$site.log"' EXIT
"$cesia" doc --site "$site" > "$site.log" 2>&1 &
site_job=$!

# The two paths side by side: one after the other, this was the longest part on a single core.
each_folder() {
  for folder in tests/lang tests/celestial src/std; do
    "$cesia" test "$folder" $1
  done
}
each_folder "" &
each_folder --no-spec
wait $!
dune test 2>&1 | tail -5
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
dirs=$(ls -d tests/*/ 2>/dev/null || true)
skip() {  # folder, reason
  echo "$1 skipped: $2"
  dirs=$(echo "$dirs" | grep -v "^$1/\$")
}
pkg-config --exists sdl3 sdl3-ttf 2>/dev/null || skip tests/sdl "SDL3 not found"
skip tests/material "tools/check.sh runs it"
command -v g++ > /dev/null || skip tests/cpp "no g++"
pkg-config --exists libsodium 2>/dev/null || skip tests/crypto "no libsodium"
pkg-config --exists openssl 2>/dev/null || skip tests/tls "no OpenSSL"
"$cesia" run tests/sqlite/has-sqlite.ce > /dev/null 2>&1 || skip tests/sqlite "no SQLite"
tools/golden.sh $dirs
# cesia do has no --no-spec, and native code runs the same on both paths.
tools/golden.sh --no-spec $(echo "$dirs" | grep -vE '^tests/(project|columns|cpp|tls|sdl|site)/$')
wait "$site_job" || { cat "$site.log"; exit 1; }
