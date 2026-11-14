#!/usr/bin/env bash
# The full suite on one path of the engine, but the tests slow by nature (name.slow, and the files of tests/slow), which
# tools/check.sh runs past the change loop, as it builds Cesia's own site.
#   tools/test.sh             the typed path, and the OCaml tests: the change loop
#   tools/test.sh --no-spec   the other path, without the versions by type: tools/check.sh runs it past the loop, the CI
#                             after the first; a test that runs the same on both paths runs only in the first
# Its parts run side by side: the examples of each folder, the golden tests and the OCaml tests.
set -eu
cd "$(dirname "$0")/.."
path=""
case "$*" in
  "") ;;
  --no-spec) path=--no-spec ;;
  *) echo "usage: tools/test.sh [--no-spec]" >&2; exit 2 ;;
esac
dune build 2>&1 | head -60
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
cesia=_build/default/src/bin/main.exe
logs=$(mktemp -d)
jobs=()
# shellcheck disable=SC2016
trap 'kill ${jobs[@]+"${jobs[@]}"} 2> /dev/null || true; rm -rf "$logs"' EXIT
# Cesia keeps the packages it loads in the folder of caches: the tests have their own, empty at the start.
export XDG_CACHE_HOME="$logs/cache"
# OpenBLAS's OpenMP threads, once a product is done, spin a while on a core before they sleep: with every test at once,
# those cores are taken from the others for nothing (tests/lang: 1.3 s of CPU on each path). Here they sleep at once.
export OMP_WAIT_POLICY=passive

# Each folder in a run of its own, all at once: one that waited for the folder before it ran alone at the end.
folders=()
for folder in tests/lang tests/celestial src/std; do
  log="$logs/${folder//\//-}.log"
  "$cesia" test "$folder" $path > "$log" 2>&1 &
  jobs+=($!)
  folders+=("$!:$log")
done

# The OCaml tests, beside the rest, on the first path alone: they have no other. Their end when they pass, all they said
# when one fails.
dune=""
if [ -z "$path" ]; then
  dune test > "$logs/dune.log" 2>&1 &
  dune=$!
  jobs+=($dune)
fi
dirs=$(ls -d tests/*/ 2>/dev/null || true)
skip() {  # folder, reason
  echo "$1 skipped: $2"
  dirs=$(echo "$dirs" | grep -v "^$1/\$")
}
command -v g++ > /dev/null || skip tests/cpp "no g++"
pkg-config --exists libsodium 2>/dev/null || skip tests/crypto "no libsodium"
pkg-config --exists openssl 2>/dev/null || skip tests/tls "no OpenSSL"
"$cesia" run tests/sqlite/has-sqlite.ce > /dev/null 2>&1 || skip tests/sqlite "no SQLite"
{ command -v python3 && command -v prlimit && unshare -rn true; } > /dev/null 2>&1 || skip tests/tabs "no python3, prlimit or unshare -rn"
"$cesia" run --allow ffi=SDL3_ttf,read=/usr/share/fonts tests/fonts/has-font.ce > /dev/null 2>&1 || skip tests/fonts "no SDL3_ttf or Noto Sans Medium"
CESIA_JIT_SHOW=1 "$cesia" version 2>&1 | grep -q '^jit: off' && skip tests/jit "no JIT on this machine"
# An engine that an earlier build made for this machine, kept in git: another system or compiler has none for its tag.
tag=$("$cesia" run tests/native/tag.ce)
if [ -f "tests/native/older/echo-$tag.cmxs" ]; then dirs="$dirs tests/native/older/"; else echo "tests/native/older skipped: no older engine for $tag"; fi
golden=0
tools/golden.sh $path --quick $dirs || golden=1

failed=$golden
if [ -n "$dune" ]; then
  if wait "$dune"; then
    tail -5 "$logs/dune.log"
  else
    cat "$logs/dune.log"
    failed=1
  fi
fi
for f in "${folders[@]}"; do
  wait "${f%%:*}" || failed=1
  cat "${f#*:}"
done
jobs=()
exit "$failed"
