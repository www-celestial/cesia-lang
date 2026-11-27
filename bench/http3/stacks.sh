#!/usr/bin/env bash
# stacks.sh PROFILE [ROUNDS]: is a lossy HTTP/3 download slow because of Cesia or because of its QUIC stack? One
# download of 1 MB on a new connection per case and round, the order turned each round, ROUNDS rounds (21): Cesia over
# HTTP/3 and HTTP/1.1, OpenSSL's QUIC alone (bare-h3, its own loop) with quic-go's client and with OpenSSL's (bare-get),
# ngtcp2 with each of its congestion controls, quic-go. The client is quic-go's (load) but for bare-get. JSON lines in
# $RES/stacks-PROFILE.jsonl; stats.py gives the medians, their intervals and the tests between two cases.
set -euo pipefail
. "$(dirname "$0")/env.sh"
profile=$1
in_ns "$profile" "stacks $profile" "$0" "$@"
rounds=${2:-21}
out=$RES/stacks-$profile.jsonl
trap stop_servers EXIT
cases=(${CASES:-cesia:h3 bare:h3 bare:get ngtcp2-reno:h3 ngtcp2-cubic:h3 ngtcp2-bbr:h3 quicgo:h3 cesia:h1})
# The servers of the cases asked, no other.
for s in $(printf '%s\n' "${cases[@]}" | cut -d: -f1 | sort -u); do start_server $s; done
for ((r = 1; r <= rounds; r++)); do
  k=0
  for x in $(rotate $((r - 1)) "${cases[@]}"); do
    s=${x%:*} p=${x#*:} k=$((k + 1))
    if [ "$p" = get ]; then
      taskset -c "$LOAD_CPUS" "$BENCH/bin/bare-get" 127.0.0.1 "${PORT[$s]}" 1 |
        sed "s/}\$/,\"server\":\"$s\",\"proto\":\"bare-get\",\"profile\":\"$profile\",\"round\":\"$r\",\"order\":\"$k\"}/" >>"$out"
    else
      run_case "$out" "$s" -proto "$p" -url "https://127.0.0.1:${PORT[$s]}/" -download 1000000 -d 0.001 -n 1 \
        -tag server="$s" -tag profile="$profile" -tag round=$r -tag order=$k
    fi
  done
  echo "$(date +%H:%M:%S) stacks $profile round $r of $rounds" >&2
done
