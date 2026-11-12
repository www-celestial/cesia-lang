#!/usr/bin/env bash
# Load speed: a corpus of small functions.
set -eu
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
# Cold: the lexer, the parser and the resolver, with an empty cache of loaded packages each time; warm: from it.
top=$(mktemp -d)
trap 'chmod -R u+rwx "$top"; rm -r "$top"' EXIT
corpus="$top/corpus.ce"
printf 'use std/io\n' > "$corpus"
for i in $(seq 1 40000); do
  printf 'defn f%d(a, b)\n  x = a * 2 + b\n  if x > 10\n    x - 1\n  else\n    x + 1\n  end\nend\n' "$i"
done >> "$corpus"
printf 'io.Print(1)\n' >> "$corpus"
lines=$(wc -l < "$corpus")
best() {  # the best of 3, in ms, each run with the cache folder that $1 names
  local best="" s e ms
  for i in 1 2 3; do
    s=$(date +%s%N)
    XDG_CACHE_HOME="$top/$1$i" _build/default/src/bin/main.exe run "$corpus" > /dev/null
    e=$(date +%s%N)
    ms=$(((e - s) / 1000000))
    if [ -z "$best" ] || [ "$ms" -lt "$best" ]; then best=$ms; fi
  done
  echo "$best"
}
cold=$(best cold)
XDG_CACHE_HOME="$top/warm" _build/default/src/bin/main.exe run "$corpus" > /dev/null
for i in 1 2 3; do ln -s "$top/warm" "$top/warm$i"; done
warm=$(best warm)
echo "load: $lines lines in $cold ms cold, $((lines * 1000 / (cold > 0 ? cold : 1))) lines/s; $warm ms from the cache"
