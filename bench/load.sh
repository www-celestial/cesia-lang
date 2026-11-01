#!/usr/bin/env bash
# Load speed: a corpus of about 280,000 lines of small functions.
set -eu
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
corpus=$(mktemp --suffix=.kp)
trap 'unlink "$corpus"' EXIT
for i in $(seq 1 40000); do
  printf 'function f%d(a, b)\n  x = a * 2 + b\n  if x > 10\n    x - 1\n  else\n    x + 1\n  end\nend\n' "$i"
done > "$corpus"
printf 'print(1)\n' >> "$corpus"
lines=$(wc -l < "$corpus")
best=""
for _ in 1 2 3; do
  s=$(date +%s%N)
  _build/default/bin/main.exe run "$corpus" > /dev/null
  e=$(date +%s%N)
  ms=$(((e - s) / 1000000))
  if [ -z "$best" ] || [ "$ms" -lt "$best" ]; then best=$ms; fi
done
echo "load: $lines lines in $best ms, $((lines * 1000 / (best > 0 ? best : 1))) lines/s"
