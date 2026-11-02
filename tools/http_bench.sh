#!/usr/bin/env bash
# Requests per second of http.serve against Node, one process at a time. --connections N measures only that load.
set -u
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
kepler=_build/default/bin/main.exe
client=_build/default/bench/http_load.exe
ulimit -n 100000
only=""
if [ "${1:-}" = "--connections" ]; then only=$2; fi

wait_for_port() {
  for _ in $(seq 1 50); do
    (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

measure() {  # name, port, command...
  local name=$1 port=$2
  shift 2
  "$@" &
  local pid=$!
  wait_for_port "$port" || { echo "$name: no server"; return 1; }
  if [ -n "$only" ]; then
    printf '%-8s %6s connections: %7s req/s\n' "$name" "$only" "$("$client" --port "$port" --connections "$only")"
  else
    for c in 10 100 1000; do
      printf '%-8s %6s connections: %7s req/s\n' "$name" "$c" "$("$client" --port "$port" --connections "$c")"
    done
    printf '%-8s  10 + 900 idle: %7s req/s\n' "$name" "$("$client" --port "$port" --connections 10 --idle 900)"
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
}

measure kepler 19100 "$kepler" run --allow net=:19100 bench/http.k
[ -n "$only" ] || measure node 19101 node bench/http.js
exit 0
