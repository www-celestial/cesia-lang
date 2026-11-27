#!/usr/bin/env bash
# migrate.sh PROFILE [ROUNDS] [FIRST]: the client's address changes after 2 MB of a 10 MB download (see migrate.go): quic-go
# and Cesia, HTTP/3 with migration (or a new connection when it fails, 1 s rule), HTTP/3 and HTTP/1.1 with a new
# connection at once; ROUNDS (5) rounds, the order turned each round. JSON lines in $RES/migrate-PROFILE.jsonl.
set -euo pipefail
. "$(dirname "$0")/env.sh"
profile=$1
in_ns "$profile" "migrate $profile" "$0" "$@"
rounds=${2:-5} first=${3:-1}
out=$RES/migrate-$profile.jsonl
trap stop_servers EXIT
for s in cesia quicgo; do start_server $s; done
cases=(${CASES:-quicgo:h3:migrate cesia:h3:migrate quicgo:h3:reconnect cesia:h3:reconnect quicgo:h1:reconnect cesia:h1:reconnect})
for ((r = first; r < first + rounds; r++)); do
  for x in $(rotate $((r - 1)) "${cases[@]}"); do
    IFS=: read -r s p how <<<"$x"
    run_case "$out" "$s" -proto "$p" -url "https://127.0.0.1:${PORT[$s]}/" -migrate "$how" -size 10000000 \
      -at 2000000 -detect 1 -tag server="$s" -tag profile="$profile" -tag round=$r
  done
  echo "$(date +%H:%M:%S) migrate $profile round $r ($rounds from $first) done" >&2
done
