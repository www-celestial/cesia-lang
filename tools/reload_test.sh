#!/usr/bin/env bash
# Hot reload, end to end, on a copy of tests/reload. Accepts --no-spec.
set -u
flags=${1:-}
cd "$(dirname "$0")/.."
dune build 2>&1 | head -40
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
kepler=$PWD/_build/default/bin/main.exe
dir=$(mktemp -d)
pid=""
failed=0
budget_ms=100

stop() {
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  [ -n "$pid" ] && wait "$pid" 2>/dev/null
  pid=""
}
cleanup() { stop; rm -rf "$dir"; }
trap cleanup EXIT
cp tests/reload/*.kp "$dir"

fail() {
  echo "reload: FAILED $*"
  sed 's/^/  stdout: /' "$dir/out" | tail -6
  sed 's/^/  stderr: /' "$dir/err" | tail -6
  failed=1
}

# Waits for an exact line in out or err. Returns 1 after the delay, in ms.
wait_for() {
  local limit=$(($(date +%s%N) + $3 * 1000000))
  until grep -qxF -- "$2" "$dir/$1" 2>/dev/null; do
    [ "$(date +%s%N)" -gt "$limit" ] && return 1
    sleep 0.002
  done
}

start() {
  # shellcheck disable=SC2086
  (cd "$dir" && exec "$kepler" run --watch $flags "$1") > "$dir/out" 2> "$dir/err" &
  pid=$!
  wait_for out "$2" 2000 || fail "program $1 did not start"
}

alive() { kill -0 "$pid" 2>/dev/null || fail "the program stopped: $1"; }

no_internal() {
  if grep -q "Internal error" "$dir/err"; then fail "internal error: $1"; fi
}

start app.kp "value 1"

# 1. The new code is active in under 100 ms.
t0=$(date +%s%N)
sed -i 's/^value() = 1$/value() = 2/' "$dir/app.kp"
wait_for out "value 2" 2000 || fail "1: new code never active"
ms=$((($(date +%s%N) - t0) / 1000000))
[ "$ms" -lt "$budget_ms" ] || fail "1: $ms ms, budget $budget_ms ms"
echo "reload: new code active in $ms ms"

wait_for out "fiber 2" 2000 || fail "1: a fiber still runs the old loop on the new code"

# 2. An invalid file leaves the program running, and the fixed file is picked up.
sed -i 's/^value() = 2$/value() = (/' "$dir/app.kp"
until grep -q "app.kp:" "$dir/err" 2>/dev/null; do
  sleep 0.01
  alive "2: invalid file"
  [ $((($(date +%s%N) - t0) / 1000000)) -gt 3000 ] && { fail "2: no error on stderr"; break; }
done
alive "2: invalid file"
sed -i 's/^value() = ($/value() = 3/' "$dir/app.kp"
wait_for out "value 3" 2000 || fail "2: fixed file not picked up"

# 3. A file missing for a moment, then recreated, is picked up.
sed 's/^value() = 3$/value() = 4/' "$dir/app.kp" > "$dir/copie"
rm "$dir/app.kp"
sleep 0.05
alive "3: missing file"
mv "$dir/copie" "$dir/app.kp"
wait_for out "value 4" 2000 || fail "3: recreated file not picked up"

# 4. A function that changes its return type keeps working for its callers.
wait_for out "following 5" 2000 || fail "4: following before the change"
sed -i 's/^value() = 4$/value() = "a"/' "$dir/app.kp"
wait_for out "value a" 2000 || fail "4: new return type"
wait_for out "following type" 2000 || fail "4: recompiled caller"
wait_for out "direct type" 2000 || fail "4: old code still running"
no_internal "4"
sed -i 's/^value() = "a"$/value() = 1.5/' "$dir/app.kp"
wait_for out "value 1.5" 2000 || fail "4: float return"
wait_for out "direct 2.5" 2000 || fail "4: old code with a float"

# A new function, a loaded module, a changed struct, a deleted function.
sed -i 's/^value() = 1.5$/value() = added()\nadded() = 9/' "$dir/app.kp"
wait_for out "value 9" 2000 || fail "new function"
sed -i 's/^constant() = 10$/constant() = 11/' "$dir/lib.kp"
wait_for out "lib 11" 2000 || fail "loaded module"
sed -i 's/^struct Point { x }$/struct Point { x, y = 5 }/; s/^point() = Point(1).x$/point() = Point(1).y/' "$dir/app.kp"
wait_for out "point 5" 2000 || fail "changed struct"
sed -i '/following/d; s/^added() = 9$/added() = 10/' "$dir/app.kp"
wait_for out "value 10" 2000 || fail "after a deleted function"
alive "deleted function"
no_internal "deleted function"

# A function that only read its argument starts writing it, under a loop compiled for the old one.
wait_for out "kept 1" 2000 || fail "read_kept before the change"
sed -i 's/^read_kept(xs) = xs\[1\]$/defn read_kept(xs)\n  xs[1] = 7\n  xs[1]\nend/' "$dir/app.kp"
wait_for out "kept 7" 2000 || fail "read_kept never changed"
sleep 0.02
if grep -qxF "owner 7" "$dir/out"; then fail "a function that writes changed its caller's array"; fi

# 5. File-level statements are not rerun.
n=$(grep -cxF "start" "$dir/out")
[ "$n" -eq 1 ] || fail "5: file-level statements ran $n times"
stop

# 6. A finished program restarts when a file changes.
start done.kp "done 1"
sleep 0.1
alive "6: finished program"
sed -i 's/^print("done 1")$/print("done 2")/' "$dir/done.kp"
wait_for out "done 2" 2000 || fail "6: program not restarted"
stop

# An HTTP server: a change applies when it is idle, and under load without a failed request.
sed 's/19100/19102/' bench/http.kp > "$dir/server.kp"
get() {
  exec 3<>/dev/tcp/127.0.0.1/19102
  printf 'GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n' >&3
  tail -c 1000 <&3 | tail -1
  exec 3<&-
}
(cd "$dir" && exec "$kepler" run --watch $flags --allow net=:19102 server.kp) > "$dir/out" 2> "$dir/err" &
pid=$!
for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/19102) 2>/dev/null && break; sleep 0.05; done
[ "$(get)" = "Kepler" ] || fail "server: first answer"
sed -i 's/body: "Kepler"/body: "Idle"/' "$dir/server.kp"
sleep 0.15
[ "$(get)" = "Idle" ] || fail "server: a change while idle"
_build/default/bench/http_load.exe --port 19102 --connections 20 --seconds 1 > "$dir/load" 2>&1 &
load=$!
sleep 0.3
sed -i 's/body: "Idle"/body: "Busy"/' "$dir/server.kp"
sleep 0.2
[ "$(get)" = "Busy" ] || fail "server: a change under load"
wait "$load" || fail "server: a request failed during the reload: $(cat "$dir/load")"
stop

# 8. A window keeps its state through a reload, under SDL's dummy driver.
if pkg-config --exists sdl3 sdl3-ttf 2>/dev/null; then
  cp fonts/JetBrainsMono-Regular.ttf "$dir/font.ttf"
  (cd "$dir" && SDL_VIDEODRIVER=dummy exec "$kepler" run --watch $flags --allow ffi=SDL3,ffi=SDL3_ttf window.kp) \
    > "$dir/out" 2> "$dir/err" &
  pid=$!
  # Waits for a line that starts with this text, and prints the last one.
  latest() {
    local limit=$(($(date +%s%N) + $2 * 1000000))
    until grep -q "^$1" "$dir/out" 2>/dev/null; do
      [ "$(date +%s%N)" -gt "$limit" ] && return 1
      sleep 0.002
    done
    grep "^$1" "$dir/out" | tail -1
  }
  latest "version 1 [1-9]" 2000 > /dev/null || fail "window: no frame after an event"
  seen=$(grep '^version 1 ' "$dir/out" | tail -1 | cut -d' ' -f3)
  sed -i 's/^version() = 1$/version() = 2/' "$dir/window.kp"
  latest "version 2 " 200 > /dev/null || fail "window: a changed view never ran"
  first=$(grep -m1 '^version 2 ' "$dir/out" | cut -d' ' -f3)
  [ "${first:-0}" -ge "$seen" ] || fail "window: the state restarted, from $seen to $first"
  sed -i 's/^finished() = false$/finished() = true/' "$dir/window.kp"
  latest "ended " 500 > /dev/null || fail "window: a changed update never ran"
  stop
fi

[ "$failed" -eq 0 ] && echo "reload: ok"
exit "$failed"
