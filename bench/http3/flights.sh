#!/usr/bin/env bash
# flights.sh PROFILE [N]: N (3) downloads of 1 MB on a new connection from Cesia (HTTP/3), OpenSSL's QUIC alone and
# quic-go, the client writing quic-go's qlog of each connection in $BENCH/qlog/PROFILE/SERVER; then the picture of what
# the client received at each round trip (flights-svg.py) in $RES/flights-PROFILE.svg.
set -euo pipefail
. "$(dirname "$0")/env.sh"
profile=$1
in_ns "$profile" "flights $profile" "$0" "$@"
n=${2:-3}
q=$BENCH/qlog/$profile
trap stop_servers EXIT
for s in cesia bare quicgo; do start_server $s; done
for s in quicgo bare cesia; do
  mkdir -p "$q/$s"
  for ((i = 1; i <= n; i++)); do
    QLOGDIR=$q/$s load -proto h3 -url "https://127.0.0.1:${PORT[$s]}/" -download 1000000 -d 0.001 -n 1 \
      -tag server=$s -tag profile="$profile" >>"$RES/flights-$profile.jsonl"
  done
done
python3 -I "$HERE/flights-svg.py" "$RES/flights-$profile.svg" "quic-go=$q/quicgo" "OpenSSL alone=$q/bare" \
  "Cesia (OpenSSL)=$q/cesia"
