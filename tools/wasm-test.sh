#!/usr/bin/env bash
# The golden tests of the folders given, native and compiled to WebAssembly in Node: each name.ce with a name.expected
# (and no name.cmd, name.args, name.stdin or name.flags, which only cesia run takes) runs with cesia run, then is built
# with cesia build --target wasm and run with node name.js, in a copy of its folder; the two outputs, stdout then stderr
# and an "exit N" line, must be the same, byte for byte. A program that uses what the build doesn't compile yet is
# skipped and counted, with what stopped it; a program whose load fails must fail the same way at the build.
#   tools/wasm-test.sh [-v] FOLDER...     -v: name each test and how it went
set -u
cd "$(dirname "$0")/.."
root=$PWD
cesia="$root/_build/default/src/bin/main.exe"
verbose=0
[ "${1:-}" = "-v" ] && { verbose=1; shift; }
command -v node > /dev/null || { echo "wasm-test: node is needed" >&2; exit 2; }
# A program with fibers waits through JavaScript Promise Integration (JSPI), which Node has from 26 on: in an older Node
# such a program stops at its first wait with the message below, and counts as skipped, not as different.
jspi=1
node -e 'process.exit(typeof WebAssembly.Suspending === "function" ? 0 : 1)' || jspi=0
nojspi="Fibers need JavaScript Promise Integration"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"
same=0 loads=0 differ=0 skipped=0
: > "$tmp/skips"
for dir in "$@"; do
  dir=${dir%/}
  copy="$tmp/$(echo "$dir" | tr / _)"
  cp -r "$dir" "$copy"
  for t in "$copy"/*.ce; do
    name=$(basename "$t" .ce)
    [ -f "$copy/$name.expected" ] || continue
    for x in cmd args stdin flags; do [ -f "$copy/$name.$x" ] && continue 2; done
    native=$(cd "$copy" && "$cesia" run "$name.ce" 2>&1 < /dev/null; echo "exit $?")
    built=$(cd "$copy" && "$cesia" build --target wasm "$name.ce" 2>&1; echo "exit $?")
    if [ "$built" != "exit 0" ]; then
      if grep -q "isn't compiled to WebAssembly yet" <<< "$built"; then
        skipped=$((skipped + 1))
        grep -o "[^:]*isn't compiled to WebAssembly yet" <<< "$built" | head -1 | sed 's/^ *//' >> "$tmp/skips"
        [ $verbose = 1 ] && echo "skip $dir/$name: $(grep -o "[^:]*isn't compiled to WebAssembly yet" <<< "$built" | head -1)"
      elif [ "$built" = "$native" ]; then
        loads=$((loads + 1))
        [ $verbose = 1 ] && echo "load $dir/$name"
      else
        differ=$((differ + 1))
        echo "DIFFER at build: $dir/$name"
        diff <(echo "$native") <(echo "$built") | head -10
      fi
      continue
    fi
    ran=$(cd "$copy" && node "$name.js" 2>&1 < /dev/null; echo "exit $?")
    if [ "$ran" = "$native" ]; then
      same=$((same + 1))
      [ $verbose = 1 ] && echo "same $dir/$name"
    elif [ $jspi = 0 ] && grep -q "$nojspi" <<< "$ran"; then
      skipped=$((skipped + 1))
      echo "fibers: this Node has no JSPI" >> "$tmp/skips"
      [ $verbose = 1 ] && echo "skip $dir/$name: fibers, this Node has no JSPI"
    else
      differ=$((differ + 1))
      echo "DIFFER: $dir/$name"
      diff <(echo "$native") <(echo "$ran") | head -10
    fi
  done
done
# The modules that a JavaScript module imports from its own folder come beside the program with it, and the loader
# imports at the start only those that js.Call names: tests/wasm/beside, run in Node.
if [ $jspi = 1 ]; then
  cp -r tests/wasm/beside "$tmp/beside"
  ran=$(cd "$tmp/beside" && "$cesia" build --target wasm page.ce 2>&1 && node page.js 2>&1 < /dev/null; echo "exit $?")
  if [ "$ran" = "$(printf 'beside later\nexit 0')" ] && [ ! -f "$tmp/beside/unused.js" ] && grep -q 'new Map(\["./glue.js"\]' "$tmp/beside/page.js"; then
    same=$((same + 1))
    [ $verbose = 1 ] && echo "same tests/wasm/beside"
  else
    differ=$((differ + 1))
    echo "DIFFER: tests/wasm/beside"
    echo "$ran" | head -10
  fi
fi
echo "wasm-test: $same same, $loads load errors the same at the build, $differ different, $skipped skipped"
if [ -s "$tmp/skips" ]; then
  echo "skipped for:"
  sort "$tmp/skips" | uniq -c | sort -rn | head -25
fi
[ $differ = 0 ]
