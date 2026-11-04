#!/usr/bin/env bash
# Project checks. Fails at the first problem, with a message.
set -u
cd "$(dirname "$0")/.."

fail() { echo "check: $1" >&2; exit 1; }

# Budget: 15,000 handwritten lines (src/lib/super.ml and src/lib/embedded.ml are generated).
lines=$(cat $(ls src/lib/*.ml src/lib/*.mli src/bin/*.ml src/sys/*.ml src/sys/*.mli src/sys/*.ml.in 2>/dev/null | grep -vE 'src/lib/(super|embedded)\.ml$|src/sys/backend\.ml$') 2>/dev/null | wc -l)
[ "$lines" -le 15000 ] || fail "over budget: $lines lines of 15000"

# File names are separated with -. OCaml can't: a file name is a module name there.
if hits=$(find . \( -name '*_*.ce' -o -name '*_*.cen' -o -name '*_*.sh' \) -not -path './_build/*' -not -path './docs/*' 2>/dev/null | grep .); then
  fail "a file name with _:
$hits"
fi

# Forbidden words in src/lib/.
if hits=$(grep -nE '\bObj\b|unsafe|\bexternal\b|Marshal|\bUnix\b' src/lib/*.ml src/lib/*.mli 2>/dev/null); then
  fail "forbidden word in src/lib/:
$hits"
fi

# No -unsafe in a dune file.
if hits=$(grep -rn --include=dune -e '-unsafe' . --exclude-dir=_build --exclude-dir=.git 2>/dev/null); then
  fail "-unsafe in a dune file:
$hits"
fi

# C and unsafe code stay in src/sys/, and it stays small.
if hits=$(grep -nE '\bObj\b|Marshal' src/sys/*.ml src/sys/*.mli src/sys/*.ml.in 2>/dev/null); then
  fail "forbidden word in src/sys/:
$hits"
fi
if hits=$(find . \( -name '*.c' -o -name '*.h' \) -not -path './src/sys/*' -not -path './_build/*' -not -path './.git/*' 2>/dev/null | grep .); then
  fail "C file outside src/sys/:
$hits"
fi
c_lines=$(cat src/sys/stubs.c src/sys/ffi.c src/sys/linalg.c | wc -l)
[ "$c_lines" -le 350 ] || fail "the C of src/sys/ has $c_lines lines, the budget is 350"

# Change loop: a touched .ml, rebuilt and tested in under 5 s, in the dev profile.
budget_ms=5000
dune build 2>&1 | head -20
backup=$(mktemp)
cp src/lib/messages.ml "$backup"
trap 'cp "$backup" src/lib/messages.ml; rm -f "$backup"' EXIT
echo "(* check *)" >> src/lib/messages.ml
s=$(date +%s%N)
tools/test.sh > /dev/null 2>&1 || fail "tools/test.sh fails"
ms=$((($(date +%s%N) - s) / 1000000))
[ "$ms" -lt "$budget_ms" ] || fail "change loop: $ms ms, budget $budget_ms ms"

# Past the budget: C++ to compile, TLS to shake hands over, and windows to open, on the path tools/test.sh leaves out for them.
slow=""
if pkg-config --exists sdl3 sdl3-ttf 2>/dev/null; then
  tools/golden.sh tests/material > /dev/null 2>&1 || fail "tests/material fails"
  slow="tests/material tests/sdl"
fi
command -v g++ > /dev/null && slow="$slow tests/cpp"
pkg-config --exists openssl 2>/dev/null && slow="$slow tests/tls"
if [ -n "$slow" ]; then
  # shellcheck disable=SC2086
  tools/golden.sh --no-spec $slow > /dev/null 2>&1 || fail "--no-spec fails on $slow"
fi

echo "check: ok ($lines lines, change loop in $ms ms)"
