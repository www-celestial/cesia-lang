#!/usr/bin/env bash
# Project checks. Fails at the first problem, with a message.
set -u
cd "$(dirname "$0")/.."

fail() { echo "check: $1" >&2; exit 1; }

# Budget: 28,000 handwritten lines of the core, src/lib, src/bin and src/sys, the ceiling of the owner (raised from 26,000
# on 2026-11-08, for the speed of maps and loops, and from 27,000 on 2026-11-12, for the load of packages)
# (src/lib/super.ml, src/lib/embedded.ml, src/lib/casefold.ml and src/sys/backend.ml are generated). The plugins the
# binary loads at their first use, src/jit, src/sqlite, src/testing, src/debug and src/native, are outside it.
lines=$(cat $(ls src/lib/*.ml src/lib/*.mli src/bin/*.ml src/sys/*.ml src/sys/*.mli src/sys/*.ml.in 2>/dev/null | grep -vE 'src/lib/(super|embedded|casefold)\.ml$|src/sys/backend\.ml$') 2>/dev/null | wc -l)
[ "$lines" -le 28000 ] || fail "over budget: $lines lines of the core of 28000"

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
if hits=$(grep -nE '\bObj\b|Marshal' src/sys/*.ml src/sys/*.mli src/sys/*.ml.in src/sqlite/*.ml 2>/dev/null); then
  fail "forbidden word in src/sys/:
$hits"
fi
if hits=$(find . \( -name '*.c' -o -name '*.h' \) -not -path './src/sys/*' -not -path './_build/*' -not -path './.git/*' 2>/dev/null | grep .); then
  fail "C file outside src/sys/:
$hits"
fi
# src/sys/mir/ is MIR, third-party: outside the budget, as generated files are. 520 lines (raised from 500 on 2026-11-13,
# for the JIT's context of MIR per unit and its level 2 made in another domain).
c_lines=$(cat src/sys/stubs.c src/sys/ffi.c src/sys/linalg.c src/sys/jit.c | wc -l)
[ "$c_lines" -le 520 ] || fail "the C of src/sys/ has $c_lines lines, the budget is 520"

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

# Past the budget: C++ to compile, TLS to shake hands over and the loops the JIT makes native, on the path tools/test.sh
# leaves out for them.
slow=""
command -v g++ > /dev/null && slow="$slow tests/cpp"
pkg-config --exists openssl 2>/dev/null && slow="$slow tests/tls"
CESIA_JIT_SHOW=1 "$PWD/_build/default/src/bin/main.exe" version 2>&1 | grep -q '^jit: off' || slow="$slow tests/jit"
if [ -n "$slow" ]; then
  # shellcheck disable=SC2086
  tools/golden.sh --no-spec $slow > /dev/null 2>&1 || fail "--no-spec fails on $slow"
fi

# The tests slow by nature (name.slow, and the files of tests/slow), on both paths, and Cesia's own site, which GitHub
# Pages publishes: a text of the docs with a [Name] that leads nowhere, or a block of the book that gives another value,
# fails here and there.
tools/golden.sh --both --slow tests/*/ > /dev/null 2>&1 || fail "a test marked slow fails: tools/golden.sh --both --slow tests/*/"
# Their own folder of caches, empty at the start, as in tools/test.sh: none of the person's packages, none left there.
cache=$(mktemp -d)
for path in "" --no-spec; do
  XDG_CACHE_HOME="$cache" "$PWD/_build/default/src/bin/main.exe" test tests/slow $path > /dev/null 2>&1 \
    || { rm -rf "$cache"; fail "a slow test fails: cesia test tests/slow $path"; }
done
rm -rf "$cache"
site=$(mktemp -d)
"$PWD/_build/default/src/bin/main.exe" doc --site "$site" > /dev/null || fail "Cesia's site doesn't build"
rm -rf "$site"

echo "check: ok ($lines lines of the core, change loop in $ms ms)"
