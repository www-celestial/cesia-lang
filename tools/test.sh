#!/usr/bin/env bash
# The full suite, on both paths, but the tests slow by nature (name.slow), which tools/check.sh runs past the change loop,
# as it builds Cesia's own site. Its parts run side by side: the examples of each folder on each path, and the golden tests.
set -eu
cd "$(dirname "$0")/.."
dune build 2>&1 | head -60
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
cesia=_build/default/src/bin/main.exe
logs=$(mktemp -d)
jobs=()
# shellcheck disable=SC2016
trap 'kill ${jobs[@]+"${jobs[@]}"} 2> /dev/null || true; rm -rf "$logs"' EXIT

each_folder() {
  for folder in tests/lang tests/celestial src/std; do
    "$cesia" test "$folder" $1
  done
}
each_folder "" > "$logs/spec.log" 2>&1 &
jobs+=($!)
each_folder --no-spec > "$logs/no-spec.log" 2>&1 &
jobs+=($!)

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
golden=0
tools/golden.sh --both --quick $dirs || golden=1

failed=$golden
for part in spec no-spec; do
  if wait "${jobs[0]}"; then
    cat "$logs/$part.log"
  else
    cat "$logs/$part.log"
    failed=1
  fi
  jobs=("${jobs[@]:1}")
done
exit "$failed"
