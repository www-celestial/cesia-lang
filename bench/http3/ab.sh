#!/usr/bin/env bash
# ab.sh [ROUNDS]: A/B of Cesia's TCP path, the binary of this branch against the binary of main, both running the
# same file, serve-tcp.ce (serve.ce without HTTP/3); HTTPS HTTP/1.1, -c 16, -w 1 -d 5, clean link, ROUNDS (21)
# rounds, main first in the odd rounds. JSON lines in $RES/ab.jsonl.
set -euo pipefail
. "$(dirname "$0")/env.sh"
in_ns clean "ab" "$0" "$@"
rounds=${1:-21}
out=$RES/ab.jsonl
trap stop_servers EXIT
start_server cesia-main
start_server cesia-quic
for ((r = 1; r <= rounds; r++)); do
  if ((r % 2)); then order="cesia-main cesia-quic"; else order="cesia-quic cesia-main"; fi
  for s in $order; do
    run_case "$out" "$s" -proto h1 -url "https://127.0.0.1:${PORT[$s]}/" -c 16 -w 1 -d 5 \
      -tag binary="${s#cesia-}" -tag round=$r
  done
  echo "$(date +%H:%M:%S) ab round $r/$rounds done" >&2
done
