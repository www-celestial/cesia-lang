#!/usr/bin/env bash
# The full suite, on both paths.
set -eu
cd "$(dirname "$0")/.."
dune build 2>&1 | head -60
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
kepler=_build/default/bin/main.exe

run_tests() {  # folder [--no-spec]: skipped if the folder has no .kp
  [ -n "$(find "$1" -name '*.kp' 2>/dev/null | head -1)" ] || return 0
  "$kepler" test "$1" ${2:-}
}

run_tests tests/lang
run_tests tests/celestial
run_tests std
run_tests tests/lang --no-spec
run_tests tests/celestial --no-spec
run_tests std --no-spec
dune test 2>&1 | tail -5
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
dirs=$(ls -d tests/*/ 2>/dev/null || true)
tools/golden.sh $dirs
tools/golden.sh --no-spec $dirs
