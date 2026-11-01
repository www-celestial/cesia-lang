#!/usr/bin/env bash
# The full suite, on both paths.
set -eu
cd "$(dirname "$0")/.."
dune build 2>&1 | head -60
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
kepler=_build/default/bin/main.exe

for flag in "" --no-spec; do
  for folder in tests/lang tests/celestial std; do
    "$kepler" test "$folder" $flag
  done
done
dune test 2>&1 | tail -5
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
dirs=$(ls -d tests/*/ 2>/dev/null || true)
skip() {  # folder, reason
  echo "$1 skipped: $2"
  dirs=$(echo "$dirs" | grep -v "^$1/\$")
}
pkg-config --exists sdl3 sdl3-ttf 2>/dev/null || skip tests/sdl "SDL3 not found"
command -v g++ > /dev/null || skip tests/cpp "no g++"
pkg-config --exists libsodium 2>/dev/null || skip tests/crypto "no libsodium"
pkg-config --exists openssl 2>/dev/null || skip tests/tls "no OpenSSL"
tools/golden.sh $dirs
# kepler do has no --no-spec, and what C does costs the same on both paths.
tools/golden.sh --no-spec $(echo "$dirs" | grep -vE '^tests/(project|cpp|crypto|tls)/$')
