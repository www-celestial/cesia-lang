#!/usr/bin/env bash
# Memory per parked fiber: the peak of 100,000 parked fibers against the peak of none. Fails above 8 KB.
set -eu
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
count=100000
limit_kb=8
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
peak_kb() {  # number of fibers
  sed "s/COUNT/$1/" bench/fibers.kp > "$dir/fibers.kp"
  python3 -I -c 'import resource, subprocess, sys
subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL)
print(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)' _build/default/bin/main.exe run "$dir/fibers.kp"
}
base=$(peak_kb 1)
full=$(peak_kb "$count")
size=$(awk -v f="$full" -v b="$base" -v n="$count" 'BEGIN { printf "%.2f", (f - b) / n }')
echo "fibers: $size KB per parked fiber"
awk -v s="$size" -v l="$limit_kb" 'BEGIN { exit !(s < l) }'
