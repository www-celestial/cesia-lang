#!/usr/bin/env bash
# The gate of the server: tools/http-bench.sh's loads, short, against thresholds. It fails if one request fails, if
# Cesia answers fewer requests per second than its floors or than Node where Node is installed, if its 99th percentile
# goes past 10 ms at 100 connections, if an idle connection takes more than 4 KB, or if two workers don't give one and
# a half times one process. The floors are those of a 2015 laptop's core (i7-4720HQ) with a margin: HTTP_GATE_SCALE=0.5
# halves them on a slower machine. Run it alone, as every benchmark: it takes about a minute.
set -u
export LC_ALL=C
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
cesia=$PWD/_build/default/src/bin/main.exe
client=$PWD/_build/default/bench/http_load.exe
scale=${HTTP_GATE_SCALE:-1}
ulimit -n 100000
failed=0
server=""
trap '[ -z "$server" ] || kill "$server" 2> /dev/null' EXIT
pin() { if command -v taskset > /dev/null; then exec taskset -c "$@"; else shift; exec "$@"; fi; }

wait_for_port() {
  for _ in $(seq 1 100); do
    (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && return 0
    sleep 0.05
  done
  return 1
}

rss_kb() {
  local total=0 kb p
  for p in $1 $(pgrep -P "$1"); do
    kb=$(awk '/^VmRSS/ { print $2 }' "/proc/$p/status" 2>/dev/null)
    total=$((total + ${kb:-0}))
  done
  echo "$total"
}

start() {  # port, cpus, command...
  local port=$1 cpus=$2
  shift 2
  (pin "$cpus" "$@" > /dev/null) &
  server=$!
  wait_for_port "$port" || { echo "gate: no server on $port"; exit 1; }
  sleep 0.2
}

stop() { kill "$server" 2> /dev/null; wait "$server" 2> /dev/null; server=""; }

load() {  # name, port, cpus, client arguments...: sets rps_NAME and p99_NAME, counts failures
  local name=$1 port=$2 cpus=$3 out
  shift 3
  out=$(pin "$cpus" "$client" --port "$port" --seconds 2 "$@")
  read -r rps p50 p99 lost <<< "$out"
  printf -v "rps_$name" '%s' "$rps"
  printf -v "p99_$name" '%s' "$p99"
  printf 'gate: %-22s %7s req/s, p99 %6s ms, %s failed\n' "$name" "$rps" "$p99" "$lost"
  [ "$lost" = 0 ] || { echo "gate: FAIL, $name: $lost requests failed"; failed=1; }
}

at_least() {  # what, value, floor
  if awk -v v="$2" -v f="$3" 'BEGIN { exit !(v >= f) }'; then echo "gate: ok   $1: $2 >= $3"
  else echo "gate: FAIL $1: $2 < $3"; failed=1; fi
}

at_most() {  # what, value, ceiling
  if awk -v v="$2" -v c="$3" 'BEGIN { exit !(v <= c) }'; then echo "gate: ok   $1: $2 <= $3"
  else echo "gate: FAIL $1: $2 > $3"; failed=1; fi
}

floor() { awk -v a="$1" -v s="$scale" 'BEGIN { printf "%d", a * s }'; }

start 19100 0 "$cesia" run --allow net=:19100 bench/http.ce
load kept100 19100 1 --connections 100
load kept1000 19100 1 --connections 1000
load json100 19100 1 --connections 100 --path /json
load new100 19100 1 --connections 100 --new
before=$(rss_kb "$server")
(pin 1 "$client" --port 19100 --seconds 3 --connections 1 --idle 10000 > /dev/null) &
idler=$!
sleep 1.5
idle_kb=$(awk -v h="$(rss_kb "$server")" -v b="$before" 'BEGIN { printf "%.2f", (h - b) / 10000 }')
wait "$idler"
stop

at_least "kept connections, 100" "$rps_kept100" "$(floor 40000)"
at_least "kept connections, 1000" "$rps_kept1000" "$(floor 25000)"
at_least "JSON, 100" "$rps_json100" "$(floor 30000)"
at_least "new connections, 100" "$rps_new100" "$(floor 15000)"
at_most "p99 ms, kept connections, 100" "$p99_kept100" 10
at_most "KB per idle connection" "$idle_kb" 4

if command -v node > /dev/null; then
  start 19101 0 node bench/http.js
  load node_kept100 19101 1 --connections 100
  load node_new100 19101 1 --connections 100 --new
  stop
  at_least "kept connections, 100, against Node" "$rps_kept100" "$rps_node_kept100"
  at_least "new connections, 100, against Node" "$rps_new100" "$rps_node_new100"
fi

# Two workers on two cores, the client on two others, against one process there.
if [ "$(getconf _NPROCESSORS_ONLN)" -ge 4 ]; then
  start 19100 0,1 "$cesia" run --allow net=:19100 bench/http.ce
  load one_process 19100 2,3 --connections 100 --threads 2
  stop
  start 19100 0,1 "$cesia" run --workers 2 --allow net=:19100 bench/http.ce
  load two_workers 19100 2,3 --connections 100 --threads 2
  stop
  at_least "two workers against one process" "$rps_two_workers" "$(awk -v o="$rps_one_process" 'BEGIN { printf "%d", o * 1.5 }')"
fi

[ "$failed" = 0 ] && echo "gate: ok" || echo "gate: FAILED"
exit "$failed"
