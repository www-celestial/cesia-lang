#!/usr/bin/env bash
# h3off.sh [ROUNDS]: does serving HTTP/3 beside slow Cesia's TCP path? The same binary and serve.ce, HTTP/3 on (last
# argument 1, port 8443) against off (0, port 8452); HTTPS HTTP/1.1, GET /, -c 16, -w 1 -d 5, clean link, ROUNDS (7)
# rounds, off first in the odd rounds. JSON lines in $RES/h3off.jsonl.
set -euo pipefail
. "$(dirname "$0")/env.sh"
in_ns clean "h3off" "$0" "$@"
rounds=${1:-7}
out=$RES/h3off.jsonl
trap stop_servers EXIT
start_server cesia
start_server cesia-noh3
for ((r = 1; r <= rounds; r++)); do
  if ((r % 2)); then order="cesia-noh3 cesia"; else order="cesia cesia-noh3"; fi
  for s in $order; do
    run_case "$out" "$s" -proto h1 -url "https://127.0.0.1:${PORT[$s]}/" -c 16 -w 1 -d 5 \
      -tag server="$s" -tag http3="$([ $s = cesia ] && echo on || echo off)" -tag round=$r
  done
  echo "$(date +%H:%M:%S) h3off round $r/$rounds done" >&2
done
