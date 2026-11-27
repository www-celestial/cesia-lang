#!/usr/bin/env bash
# memory.sh [ROUNDS] [N]: the server's memory per idle connection, clean link. For each case, in each round (5): the
# server starts alone, 4 connections warm it for 1 s, then N (200) connections each send GET / once and stay open
# and idle 3 s; (VmRSS after - VmRSS before) / N, VmRSS summed over the server's processes (nginx: master and
# workers). JSON lines in $RES/memory.jsonl.
set -euo pipefail
. "$(dirname "$0")/env.sh"
in_ns clean "memory" "$0" "$@"
rounds=${1:-5} n=${2:-200}
out=$RES/memory.jsonl
trap stop_servers EXIT
cases=(${CASES:-cesia:h3 cesia:h1 quicgo:h3 quicgo:h1 nginx:h3 nginx:h1})
for ((r = 1; r <= rounds; r++)); do
  for x in $(rotate $((r - 1)) "${cases[@]}"); do
    s=${x%:*} p=${x#*:}
    start_server "$s"
    load -proto "$p" -url "https://127.0.0.1:${PORT[$s]}/" -c 4 -w 0 -d 1 >/dev/null 2>>"$LOGS/memory.err"
    sleep 1
    run_case "$out" "$s" -proto "$p" -url "https://127.0.0.1:${PORT[$s]}/" -hold "$n" -pid "$(server_pids "$s")" \
      -idle 3 -tag server="$s" -tag round=$r
    stop_server "$s"
  done
  echo "$(date +%H:%M:%S) memory round $r/$rounds done" >&2
done
