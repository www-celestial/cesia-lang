#!/usr/bin/env bash
# Project checks. Fails at the first problem, with a message.
set -u
cd "$(dirname "$0")/.."

fail() { echo "check: $1" >&2; exit 1; }

# Budget: 15,000 handwritten lines (src/super.ml and src/embedded.ml are generated).
lines=$(cat $(ls src/*.ml src/*.mli bin/*.ml sys/*.ml sys/*.mli sys/*.ml.in 2>/dev/null | grep -vE 'src/(super|embedded)\.ml$|sys/backend\.ml$') 2>/dev/null | wc -l)
[ "$lines" -le 15000 ] || fail "over budget: $lines lines of 15000"

# File names are separated with -. OCaml can't: a file name is a module name there.
if hits=$(find . \( -name '*_*.k' -o -name '*_*.kn' -o -name '*_*.sh' \) -not -path './_build/*' -not -path './docs/*' 2>/dev/null | grep .); then
  fail "a file name with _:
$hits"
fi

# Forbidden words in src/.
if hits=$(grep -nE '\bObj\b|unsafe|\bexternal\b|Marshal|\bUnix\b' src/*.ml src/*.mli 2>/dev/null); then
  fail "forbidden word in src/:
$hits"
fi

# No -unsafe in a dune file.
if hits=$(grep -rn --include=dune -e '-unsafe' . --exclude-dir=_build --exclude-dir=.git 2>/dev/null); then
  fail "-unsafe in a dune file:
$hits"
fi

# C and unsafe code stay in sys/, and sys/ stays small.
if hits=$(grep -nE '\bObj\b|Marshal' sys/*.ml sys/*.mli sys/*.ml.in 2>/dev/null); then
  fail "forbidden word in sys/:
$hits"
fi
if hits=$(find . \( -name '*.c' -o -name '*.h' \) -not -path './sys/*' -not -path './_build/*' -not -path './.git/*' 2>/dev/null | grep .); then
  fail "C file outside sys/:
$hits"
fi
c_lines=$(cat sys/stubs.c sys/ffi.c sys/linalg.c | wc -l)
[ "$c_lines" -le 350 ] || fail "the C of sys/ has $c_lines lines, the budget is 350"

# Change loop: a touched .ml, rebuilt and tested in under 5 s, in the dev profile.
budget_ms=5000
dune build 2>&1 | head -20
backup=$(mktemp)
cp src/messages.ml "$backup"
trap 'cp "$backup" src/messages.ml; rm -f "$backup"' EXIT
echo "(* check *)" >> src/messages.ml
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
