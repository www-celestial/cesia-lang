#!/usr/bin/env bash
# Project checks. Fails at the first problem, with a message.
set -u
cd "$(dirname "$0")/.."

fail() { echo "check: $1" >&2; exit 1; }

# Budget: 28,500 handwritten lines of the core, src/lib, src/bin and src/sys, the ceiling of the owner (raised from 26,000
# on 2026-11-08, for the speed of maps and loops, from 27,000 on 2026-11-12, for the load of packages, and from 28,000
# on 2026-11-26, for the calls of compiled code to OCaml's natives, a native table of sessions, a native Base64 and a
# pool of domains for slow calls)
# (src/lib/super.ml, src/lib/embedded.ml, src/lib/casefold.ml and src/sys/backend.ml are generated). The plugins the
# binary loads at their first use, src/jit, src/sqlite, src/testing, src/debug and src/native, are outside it.
lines=$(cat $(ls src/lib/*.ml src/lib/*.mli src/bin/*.ml src/sys/*.ml src/sys/*.mli src/sys/*.ml.in 2>/dev/null | grep -vE 'src/lib/(super|embedded|casefold)\.ml$|src/sys/backend\.ml$') 2>/dev/null | wc -l)
[ "$lines" -le 28500 ] || fail "over budget: $lines lines of the core of 28500"

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
# src/sys/mir/ is MIR, third-party: outside the budget, as generated files are. 650 lines (raised from 500 on 2026-11-13,
# for the JIT's context of MIR per unit and its level 2 made in another domain, then from 520 on 2026-11-21, for the
# openat, unlinkat and readdir of a descriptor that sys.RemoveTree walks with, which OCaml's Unix lacks, then from 560
# on 2026-11-22, for openat2, mkdirat, symlinkat, renameat, readlinkat and futimens, which the checks of read= and
# write= and sys.CopyTree work with, then from 623 on 2026-11-23, for copy_file_range, with which sys.Copy and
# sys.CopyTree copy the bytes of a file in the kernel, then from 638 on 2026-11-24, for LoadLibraryExA, with which a DLL of
# a release's lib/ finds those it needs beside it on Windows, as $ORIGIN does on Linux, then from 650 on 2026-11-26, for
# the calls of compiled code to OCaml's natives).
c_lines=$(cat src/sys/stubs.c src/sys/ffi.c src/sys/linalg.c src/sys/jit.c | wc -l)
[ "$c_lines" -le 800 ] || fail "the C of src/sys/ has $c_lines lines, the budget is 800"

# Change loop: a touched .ml, rebuilt and tested on the typed path in under 5 s, in the dev profile.
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

# Past the budget: the same tests on the other path, which the loop leaves out, then the tests slow by nature (name.slow,
# and the files of tests/slow), on both paths.
tools/test.sh --no-spec > /dev/null 2>&1 || fail "the other path fails: tools/test.sh --no-spec"
tools/test.sh --slow > /dev/null 2>&1 || fail "a test slow by nature fails: tools/test.sh --slow"

# Cesia's own site, which GitHub Pages publishes: a text of the docs with a [Name] that leads nowhere, or a block of the
# book that gives another value, fails here and there; so does a tab of the book, an example in Python, R or MATLAB, that
# prints other values than its cesia block. A tab whose language isn't installed here is skipped with a warning: the CI
# of the site runs them all. A block of Cesia's own book that names no language fails here and there too: cesia doc --site
# only warns of it, so that a book that built before still builds, and Cesia's book is held to more than that.
site=$(mktemp -d)
work=$(mktemp -d)
trap 'cp "$backup" src/lib/messages.ml; rm -f "$backup"; rm -rf "$site" "$work"' EXIT
"$PWD/_build/default/src/bin/main.exe" doc --site "$site" > /dev/null 2> "$work/site.err" || { cat "$work/site.err" >&2; fail "Cesia's site doesn't build"; }
cat "$work/site.err" >&2
grep -q 'names no language' "$work/site.err" && fail "a block of Cesia's book names no language"
"$PWD/_build/default/src/bin/main.exe" run --allow "read=$site,read=docs,read=$work,write=$work,exec=prlimit,env=CI,env=PATH" tools/tabs.ce "$site/.tabs" "$work" ||
  fail "a tab of the book fails: tools/tabs.ce"

echo "check: ok ($lines lines of the core, change loop in $ms ms)"
