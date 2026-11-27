#!/usr/bin/env bash
# rps.sh PROFILE [ROUNDS] [FIRST]: requests/s and p50/p99 latency of GET / for each server and protocol, -c 16 (and -c 1 on
# the lossy profiles), ROUNDS rounds (7 on clean, 5 on the others by default); each round runs every case once, in an
# order turned by one from the round before; FIRST (1) numbers the first round, so that a later session can add rounds. JSON lines in $RES/rps-PROFILE.jsonl.
set -euo pipefail
. "$(dirname "$0")/env.sh"
profile=$1
in_ns "$profile" "rps $profile" "$0" "$@"
first=${3:-1}
if [ "$profile" = clean ]; then rounds=${2:-7} w=1 d=5 cs="16"; else rounds=${2:-5} w=2 d=8 cs="16 1"; fi
out=$RES/rps-$profile.jsonl
trap stop_servers EXIT
for s in cesia quicgo caddy nginx; do start_server $s; done
cases=(${CASES:-cesia:h1 cesia:h3 quicgo:h1 quicgo:h2 quicgo:h3 caddy:h1 caddy:h2 caddy:h3 nginx:h1 nginx:h2 nginx:h3})
for ((r = first; r < first + rounds; r++)); do
  k=0
  for x in $(rotate $((r - 1)) "${cases[@]}"); do
    s=${x%:*} p=${x#*:} k=$((k + 1))
    for c in $cs; do
      run_case "$out" "$s" -proto "$p" -url "https://127.0.0.1:${PORT[$s]}/" -c "$c" -w $w -d $d \
        -tag server="$s" -tag profile="$profile" -tag round=$r -tag order=$k
    done
  done
  echo "$(date +%H:%M:%S) rps $profile round $r ($rounds from $first) done" >&2
done
