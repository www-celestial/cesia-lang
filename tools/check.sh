#!/usr/bin/env bash
# Project checks. Fails at the first problem, with a message.
set -u
cd "$(dirname "$0")/.."

fail() { echo "check: $1" >&2; exit 1; }

# Budget: 15,000 handwritten lines (src/super.ml and src/embedded.ml are generated).
lines=$(cat $(ls src/*.ml src/*.mli bin/*.ml 2>/dev/null | grep -vE 'src/(super|embedded)\.ml$') 2>/dev/null | wc -l)
[ "$lines" -le 15000 ] || fail "over budget: $lines lines of 15000"

# Forbidden words in src/.
if hits=$(grep -nE '\bObj\b|unsafe|\bexternal\b|Marshal' src/*.ml src/*.mli 2>/dev/null); then
  fail "forbidden word in src/:
$hits"
fi

# No -unsafe in a dune file.
if hits=$(grep -rn --include=dune -e '-unsafe' . --exclude-dir=_build --exclude-dir=.git 2>/dev/null); then
  fail "-unsafe in a dune file:
$hits"
fi

# No C in src/.
if hits=$(find src -name '*.c' -o -name '*.h' 2>/dev/null | grep .); then
  fail "C file in src/:
$hits"
fi

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

echo "check: ok ($lines lines, change loop in $ms ms)"
