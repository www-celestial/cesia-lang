# Shared by the scripts of bench/http3: paths, ports, CPU sets, the network profiles, the servers, the heavy lock.
# Sourced, not run. Every path can be overridden from the environment.

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BENCH=${BENCH:-$HOME/.cache/quic/bench}
CERTS=${CERTS:-$HOME/.cache/quic/certs}
CESIA=${CESIA:-$HOME/.cache/quic/cesia-build/default/src/bin/main.exe}
CESIA_MAIN=${CESIA_MAIN:-$HOME/.cache/quic/main-build/default/src/bin/main.exe}
GO=${GO:-/usr/local/go/bin/go}
RES=${RES:-$BENCH/results}
LOGS=$BENCH/logs
RUN=$BENCH/run
NGX=$BENCH/nginx-root
mkdir -p "$RES" "$LOGS" "$RUN/pids"
# A signal ends the script through exit, so that its EXIT trap (stop_servers, lock_release) runs.
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Two physical cores each (CPU n and n+4 are the two threads of one core on this machine): the load generator on
# cores 0 and 1, every server on cores 2 and 3.
LOAD_CPUS=${LOAD_CPUS:-0,1,4,5}
SERVER_CPUS=${SERVER_CPUS:-2,3,6,7}

declare -A PORT=([cesia]=8443 [quicgo]=8444 [caddy]=8445 [nginx]=8446 [cesia-quic]=8450 [cesia-main]=8451
  [cesia-noh3]=8452 [bare]=8460 [ngtcp2-reno]=8461 [ngtcp2-cubic]=8462 [ngtcp2-bbr]=8463)

# quic-go everywhere (load generator, quic-go server, Caddy) without UDP GSO: netem must see each datagram, not a
# 64 KB burst of them.
export QUIC_GO_DISABLE_GSO=true QUIC_GO_DISABLE_RECEIVE_BUFFER_WARNING=true

# netem_args PROFILE: the netem arguments of a profile; the delay is added to every packet, so the RTT is twice it.
netem_args() {
  case $1 in
    clean) echo "" ;;
    d25l1) echo "delay 25ms loss 1%" ;;
    d25l1r20) echo "delay 25ms loss 1% rate 20mbit" ;;
    d50l3) echo "delay 50ms loss 3%" ;;
    d100l5) echo "delay 100ms loss 5%" ;;
    *) echo "unknown profile $1 (clean d25l1 d25l1r20 d50l3 d100l5)" >&2; return 1 ;;
  esac
}

# start_server NAME: starts one server in the background, pinned to SERVER_CPUS, records its PID in $RUN/pids/NAME
# and waits until it answers on TCP and, but for the TCP-only ones, on UDP (HTTP/3).
start_server() {
  local name=$1 port=${PORT[$1]} log=$LOGS/server-$1.log h3=1 tcp=1
  case $name in
    cesia)
      taskset -c "$SERVER_CPUS" "$CESIA" run --allow ffi=ssl,ffi=crypto,net "$HERE/serve.ce" \
        "$CERTS/cert.pem" "$CERTS/key.pem" "$port" 1 "${CESIA_CC:-cubic}" >"$log" 2>&1 &
      ;;
    cesia-noh3)
      h3=0
      taskset -c "$SERVER_CPUS" "$CESIA" run --allow ffi=ssl,ffi=crypto,net "$HERE/serve.ce" \
        "$CERTS/cert.pem" "$CERTS/key.pem" "$port" 0 >"$log" 2>&1 &
      ;;
    cesia-quic | cesia-main)
      h3=0
      local bin=$CESIA
      [ "$name" = cesia-main ] && bin=$CESIA_MAIN
      taskset -c "$SERVER_CPUS" "$bin" run --allow ffi=ssl,ffi=crypto,net "$BENCH/serve-tcp.ce" \
        "$CERTS/cert.pem" "$CERTS/key.pem" "$port" >"$log" 2>&1 &
      ;;
    quicgo)
      GOMAXPROCS=4 taskset -c "$SERVER_CPUS" "$BENCH/bin/quicgo" -cert "$CERTS/cert.pem" -key "$CERTS/key.pem" \
        -port "$port" >"$log" 2>&1 &
      ;;
    caddy)
      GOMAXPROCS=4 XDG_CONFIG_HOME=$RUN/caddy XDG_DATA_HOME=$RUN/caddy taskset -c "$SERVER_CPUS" \
        "$BENCH/bin/caddy" run --config "$RUN/Caddyfile" --adapter caddyfile >"$log" 2>&1 &
      ;;
    nginx)
      # A nested user namespace where nginx is not root, so that its master does not try to drop privileges
      # (setgroups is denied in the namespace of ns.sh).
      unshare -U --map-user="${OUTER_UID:-1000}" --map-group="${OUTER_GID:-1000}" taskset -c "$SERVER_CPUS" \
        "$NGX/lib/ld-musl-x86_64.so.1" --library-path "$NGX/lib:$NGX/usr/lib" "$NGX/usr/sbin/nginx" \
        -p "$RUN/nginx" -c "$RUN/nginx.conf" -e "$LOGS/nginx-error.log" >"$log" 2>&1 &
      ;;
    bare)
      # OpenSSL's QUIC alone (openssl/bare-h3.c): 1 MB for every request, over UDP only.
      tcp=0
      taskset -c "$SERVER_CPUS" "$BENCH/bin/bare-h3" "$CERTS/cert.pem" "$CERTS/key.pem" "$port" 1000000 >"$log" 2>&1 &
      ;;
    ngtcp2-reno | ngtcp2-cubic | ngtcp2-bbr)
      # ngtcp2's example server, TLS by the system's OpenSSL, without GSO: netem must see each datagram, not a burst.
      tcp=0
      taskset -c "$SERVER_CPUS" "$BENCH/bin/ngtcp2-server" -q --no-gso --cc="${name#ngtcp2-}" -d "$BENCH/www" \
        127.0.0.1 "$port" "$CERTS/key.pem" "$CERTS/cert.pem" >"$log" 2>&1 &
      ;;
    *) echo "unknown server $name" >&2; return 1 ;;
  esac
  echo $! >"$RUN/pids/$name"
  local i
  for i in $(seq 100); do
    if { [ $tcp = 0 ] || curl -sk -o /dev/null --max-time 2 --resolve "localhost:$port:127.0.0.1" "https://localhost:$port/"; } &&
      { [ $h3 = 0 ] || curl -sk -o /dev/null --max-time 2 --http3-only --resolve "localhost:$port:127.0.0.1" "https://localhost:$port/"; }; then
      return 0
    fi
    sleep 0.1
  done
  echo "server $name did not answer on port $port; log: $log" >&2
  return 1
}

# server_pids NAME: the PID of a server and of its children (nginx's workers).
server_pids() {
  local p
  p=$(cat "$RUN/pids/$1")
  printf '%s' "$p"
  for c in $(cat /proc/"$p"/task/*/children 2>/dev/null); do printf ',%s' "$c"; done
  echo
}

# stop_server NAME: TERM, then KILL after 5 s, by the recorded PIDs only (and nginx's workers by theirs).
stop_server() {
  local f=$RUN/pids/$1 all p i
  [ -f "$f" ] || return 0
  all=$(server_pids "$1" | tr , ' ')
  kill -TERM $(cat "$f") 2>/dev/null || true
  for i in $(seq 50); do
    for p in $all; do kill -0 "$p" 2>/dev/null && break; p=; done
    [ -z "$p" ] && break
    sleep 0.1
  done
  for p in $all; do kill -KILL "$p" 2>/dev/null || true; done
  rm -f "$f"
}

# ensure_server NAME: starts the server again if it died (a crash), and writes so in $LOGS/crashes.log.
ensure_server() {
  local f=$RUN/pids/$1
  if [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null; then return 0; fi
  echo "$(date +%H:%M:%S) ${BENCH_PROFILE:-?} $1 was dead; last lines of its log:" >>"$LOGS/crashes.log"
  tail -3 "$LOGS/server-$1.log" >>"$LOGS/crashes.log" 2>/dev/null || true
  cp "$LOGS/server-$1.log" "$LOGS/server-$1-crash-$(date +%H%M%S).log" 2>/dev/null || true
  rm -f "$f"
  start_server "$1"
}

stop_servers() {
  local f
  for f in "$RUN"/pids/*; do [ -f "$f" ] && stop_server "$(basename "$f")"; done
  return 0
}

# load ARGS...: the load generator pinned to LOAD_CPUS.
load() {
  GOMAXPROCS=4 taskset -c "$LOAD_CPUS" "$BENCH/bin/load" -insecure "$@"
}

# run_case OUT SERVER LOAD-ARGS...: one measured run, its JSON line appended to OUT: the server is started again
# first if it died; if it dies during the run, a line {"mode":"crash",...} goes to $RES/crashes.jsonl.
run_case() {
  local out=$1 s=$2 rc=0
  shift 2
  ensure_server "$s"
  load "$@" >>"$out" 2>>"$LOGS/load.err" || rc=$?
  sleep 0.3
  if ! kill -0 "$(cat "$RUN/pids/$s")" 2>/dev/null; then
    printf '{"mode":"crash","server":"%s","profile":"%s","time":"%s","args":"%s"}\n' "$s" "${BENCH_PROFILE:-}" \
      "$(date +%H:%M:%S)" "$*" >>"$RES/crashes.jsonl"
  fi
  [ $rc = 0 ] || echo "failed ($rc): $s $*" >&2
  return 0
}

# rotate N LIST...: LIST turned left by N, so that each round runs the cases in another order.
rotate() {
  local n=$1
  shift
  local a=("$@") k=${#a[@]} i
  for ((i = 0; i < k; i++)); do echo "${a[$(((i + n) % k))]}"; done
}

# The heavy lock: a file shared by the jobs of this machine that holds `main` when free. HEAVY_LOCK names it; when it
# is unset, the measures run without it.
lock_take() {
  [ -n "${HEAVY_LOCK:-}" ] || { echo "HEAVY_LOCK unset: measuring without the lock" >&2; return 0; }
  local c
  while :; do
    c=$(cat "$HEAVY_LOCK" 2>/dev/null || true)
    if [ "$c" = main ]; then
      LOCK_ENTRY="quic bench $1 $(date +%H:%M)"
      printf '%s\n' "$LOCK_ENTRY" >"$HEAVY_LOCK"
      sleep 1
      [ "$(cat "$HEAVY_LOCK" 2>/dev/null)" = "$LOCK_ENTRY" ] && return 0
      LOCK_ENTRY=
    fi
    [ "$c" = "${LOCK_SEEN:-}" ] || echo "$(date +%H:%M:%S) heavy lock held by: $c" >&2
    LOCK_SEEN=$c
    sleep 2
  done
}

lock_release() {
  [ -n "${HEAVY_LOCK:-}" ] && [ -n "${LOCK_ENTRY:-}" ] || return 0
  [ "$(cat "$HEAVY_LOCK" 2>/dev/null)" = "$LOCK_ENTRY" ] && printf 'main\n' >"$HEAVY_LOCK"
  LOCK_ENTRY=
}

# in_ns PROFILE WHAT SCRIPT ARGS...: outside the namespace, takes the lock, runs SCRIPT again inside ns.sh PROFILE,
# gives the lock back and exits; inside, returns at once.
in_ns() {
  [ -n "${BENCH_NS:-}" ] && return 0
  local profile=$1 what=$2
  shift 2
  lock_take "$what"
  trap lock_release EXIT
  local rc=0
  "$HERE/ns.sh" "$profile" "$@" || rc=$?
  lock_release
  # Time for another job to take the lock before the next session of this one.
  [ -n "${HEAVY_LOCK:-}" ] && sleep "${LOCK_PAUSE:-40}"
  exit $rc
}
