#!/usr/bin/env bash
# HTTP under load: Cesia's http.Serve against Node, and Go on one core if it is installed, one server at a time. For each
# load: the requests per second, the median and the 99th percentile of the latency, the failed requests, and the memory
# of the server at the end. The loads: a tiny route and a JSON one on kept connections, a new connection per request, and
# 10 active connections beside 10,000 idle ones, which gives the memory of an idle connection. The server runs on the
# first core and the client on the second, so that neither takes the other's.
#   tools/http-bench.sh [--only cesia] [--seconds N]
# PROGRAM=bench/real/http.ce measures that server instead, alone: a small JSON API, for the JIT.
set -u
export LC_ALL=C
cd "$(dirname "$0")/.."
dune build --profile release 2>&1 | head -20
cesia=$PWD/_build/default/src/bin/main.exe
client=$PWD/_build/default/bench/http_load.exe
ulimit -n 100000
only=""
seconds=3
while [ $# -gt 0 ]; do
  case "$1" in
    --only) only=$2; shift ;;
    --seconds) seconds=$2; shift ;;
  esac
  shift
done
server_cpu=${SERVER_CPUS:-0}
client_cpu=${CLIENT_CPUS:-1}
# Runs a command on the cores given, in place of the shell that calls it: always in a subshell or in the background.
pin() { if command -v taskset > /dev/null; then exec taskset -c "$@"; else shift; exec "$@"; fi; }
server=""
trap '[ -z "$server" ] || kill "$server" 2> /dev/null' EXIT

wait_for_port() {
  for _ in $(seq 1 100); do
    (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && return 0
    sleep 0.05
  done
  return 1
}

# The resident memory of a process and of its children, in KB.
rss_kb() {
  local total=0 kb p
  for p in $1 $(pgrep -P "$1"); do
    kb=$(awk '/^VmRSS/ { print $2 }' "/proc/$p/status" 2>/dev/null)
    total=$((total + ${kb:-0}))
  done
  echo "$total"
}

row() {  # server, pid, port, label, client arguments...
  local name=$1 pid=$2 port=$3 label=$4 got
  shift 4
  got=$(pin "$client_cpu" "$client" --port "$port" --seconds "$seconds" "$@" || true)
  read -r rps p50 p99 failed <<< "$got"
  printf '%-6s %-28s %8s %8s %8s %7s %8.1f\n' "$name" "$label" "$rps" "$p50" "$p99" "$failed" "$(awk -v k="$(rss_kb "$pid")" 'BEGIN { print k / 1024 }')"
}

measure() {  # name, port, command...
  local name=$1 port=$2
  shift 2
  (pin "$server_cpu" "$@" > /dev/null) &
  local pid=$!
  server=$pid
  wait_for_port "$port" || { echo "$name: no server"; return 1; }
  sleep 0.2
  local before
  before=$(rss_kb "$pid")
  for c in 10 100 1000; do row "$name" "$pid" "$port" "/, kept, $c" --connections "$c"; done
  row "$name" "$pid" "$port" "/json, kept, 100" --connections 100 --path /json
  row "$name" "$pid" "$port" "/, new, 10" --connections 10 --new
  row "$name" "$pid" "$port" "/, new, 100" --connections 100 --new
  # The idle connections stay open while the 10 active ones run: the memory is measured with them, then per connection.
  local busy
  busy=$(rss_kb "$pid")
  (pin "$client_cpu" "$client" --port "$port" --seconds $((seconds + 2)) --connections 1 --idle 10000 > /dev/null) &
  local idler=$!
  sleep 1.5
  local held
  held=$(rss_kb "$pid")
  row "$name" "$pid" "$port" "/, kept, 10 + 10000 idle" --connections 10
  wait "$idler"
  awk -v n="$name" -v h="$held" -v u="$busy" -v b="$before" 'BEGIN { printf "%-6s %-28s %.2f KB per idle connection, %.1f MB at rest\n", n, "memory", (h - u) / 10000, b / 1024 }'
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  server=""
}

printf '%-6s %-28s %8s %8s %8s %7s %8s\n' server load req/s "p50 ms" "p99 ms" failed "RSS MB"
program=${PROGRAM:-bench/http.ce}
[ -z "$only" ] || [ "$only" = cesia ] && measure cesia 19100 "$cesia" run --allow net=:19100 "$program"
[ "$program" = bench/http.ce ] || exit 0
if [ -z "$only" ] || [ "$only" = node ]; then
  command -v node > /dev/null && measure node 19101 node bench/http.js
fi
if [ -z "$only" ] || [ "$only" = go ]; then
  if command -v go > /dev/null; then
    go build -o _build/http-go bench/http.go && GOMAXPROCS=1 measure go 19102 _build/http-go
  fi
fi
exit 0
