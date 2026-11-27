#!/usr/bin/env bash
# download.sh PROFILE [ROUNDS] [FIRST]: time per download of /bytes/1000000 (and /bytes/10000000 on clean) for each server and
# protocol, each download on a new connection (handshake and slow start included), downloads one after the other for
# 3 s (5 s on the lossy profiles, at least one); ROUNDS rounds (5), the order turned each round, FIRST (1) the number of the first.
# JSON lines in $RES/download-PROFILE.jsonl.
set -euo pipefail
. "$(dirname "$0")/env.sh"
profile=$1
in_ns "$profile" "download $profile" "$0" "$@"
rounds=${2:-5} first=${3:-1}
if [ "$profile" = clean ]; then sizes="1000000 10000000" d=3; else sizes="1000000" d=5; fi
out=$RES/download-$profile.jsonl
trap stop_servers EXIT
for s in cesia quicgo caddy nginx; do start_server $s; done
cases=(${CASES:-cesia:h1 cesia:h3 quicgo:h1 quicgo:h2 quicgo:h3 caddy:h1 caddy:h2 caddy:h3 nginx:h1 nginx:h2 nginx:h3})
for ((r = first; r < first + rounds; r++)); do
  k=0
  for x in $(rotate $((r - 1)) "${cases[@]}"); do
    s=${x%:*} p=${x#*:} k=$((k + 1))
    for n in $sizes; do
      run_case "$out" "$s" -proto "$p" -url "https://127.0.0.1:${PORT[$s]}/" -download "$n" -d $d -n 50 \
        -tag server="$s" -tag profile="$profile" -tag round=$r -tag order=$k
    done
  done
  echo "$(date +%H:%M:%S) download $profile round $r ($rounds from $first) done" >&2
done
