#!/usr/bin/env bash
# Hot reload, end to end, on a copy of tests/reload. Accepts --no-spec.
set -u
flags=${1:-}
cd "$(dirname "$0")/.."
dune build 2>&1 | head -40
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
cesia=$PWD/_build/default/src/bin/main.exe
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
cp -r tests/reload/* "$dir"

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
  (cd "$dir" && exec "$cesia" run --watch $flags "$1") > "$dir/out" 2> "$dir/err" &
  pid=$!
  wait_for out "$2" 2000 || fail "program $1 did not start"
}

alive() { kill -0 "$pid" 2>/dev/null || fail "the program stopped: $1"; }

no_internal() {
  if grep -q "Internal error" "$dir/err"; then fail "internal error: $1"; fi
}

start app.ce "value 1"

# 1. The new code is active in under 100 ms.
t0=$(date +%s%N)
sed -i 's/^value() = 1$/value() = 2/' "$dir/app.ce"
wait_for out "value 2" 2000 || fail "1: new code never active"
ms=$((($(date +%s%N) - t0) / 1000000))
[ "$ms" -lt "$budget_ms" ] || fail "1: $ms ms, budget $budget_ms ms"
echo "reload: new code active in $ms ms"

wait_for out "summed 4501500" 2000 || fail "jit: summed never ran"

wait_for out "fiber 2" 2000 || fail "1: a fiber still runs the old loop on the new code"

# 2. An invalid file leaves the program running, and the fixed file is picked up.
sed -i 's/^value() = 2$/value() = (/' "$dir/app.ce"
until grep -q "app.ce:" "$dir/err" 2>/dev/null; do
  sleep 0.01
  alive "2: invalid file"
  [ $((($(date +%s%N) - t0) / 1000000)) -gt 3000 ] && { fail "2: no error on stderr"; break; }
done
alive "2: invalid file"
sed -i 's/^value() = ($/value() = 3/' "$dir/app.ce"
wait_for out "value 3" 2000 || fail "2: fixed file not picked up"

# 3. A file missing for a moment, then recreated, is picked up.
sed 's/^value() = 3$/value() = 4/' "$dir/app.ce" > "$dir/copie"
rm "$dir/app.ce"
sleep 0.05
alive "3: missing file"
mv "$dir/copie" "$dir/app.ce"
wait_for out "value 4" 2000 || fail "3: recreated file not picked up"

# 4. A function that changes its return type keeps working for its callers.
wait_for out "following 5" 2000 || fail "4: following before the change"
sed -i 's/^value() = 4$/value() = "a"/' "$dir/app.ce"
wait_for out "value a" 2000 || fail "4: new return type"
wait_for out "following type" 2000 || fail "4: recompiled caller"
wait_for out "direct type" 2000 || fail "4: old code still running"
no_internal "4"
sed -i 's/^value() = "a"$/value() = 1.5/' "$dir/app.ce"
wait_for out "value 1.5" 2000 || fail "4: float return"
wait_for out "direct 2.5" 2000 || fail "4: old code with a float"

# A new function, a loaded module, a changed struct, a deleted function.
sed -i 's/^value() = 1.5$/value() = added()\nadded() = 9/' "$dir/app.ce"
wait_for out "value 9" 2000 || fail "new function"
sed -i 's/^Constant() = 10$/Constant() = 11/' "$dir/lib/lib.ce"
wait_for out "lib 11" 2000 || fail "loaded module"
sed -i 's/^struct Point { X }$/struct Point { X, Y = 5 }/; s/^point() = Point(1).X$/point() = Point(1).Y/' "$dir/app.ce"
wait_for out "point 5" 2000 || fail "changed struct"
sed -i 's/^struct Point { X, Y = 5 }$/struct Point\n  X\n  Y = 6\nend/' "$dir/app.ce"
wait_for out "point 6" 2000 || fail "a struct that takes the block form"
sed -i '/following/d; s/^added() = 9$/added() = 10/' "$dir/app.ce"
wait_for out "value 10" 2000 || fail "after a deleted function"
alive "deleted function"
no_internal "deleted function"

# Methods change as functions do, and a value made before its struct changed keeps them.
wait_for out "method 1" 2000 || fail "method before the change"
sed -i 's/^(p Point) Value() = 1$/(p Point) Value() = 2/' "$dir/app.ce"
wait_for out "method 2" 2000 || fail "a changed method never ran"
wait_for out "old 2" 2000 || fail "a value of the old struct lost its methods"
sed -i 's/^Point.Made() = Point(1)$/Point.Made() = Point(3)/; s/^(p Point) Value() = 2$/(p Point) Value() = p.X/' "$dir/app.ce"
wait_for out "method 3" 2000 || fail "a changed static method never ran"
sed -i 's/^(p Point) Value() = p.X$/(p Point) Value() = p.Added()\n(p Point) Added() = 4/' "$dir/app.ce"
wait_for out "method 4" 2000 || fail "a new method"
sed -i '/^(p Point) Added() = 4$/d' "$dir/app.ce"
wait_for out "method field" 2000 || fail "a deleted method still runs"
sed -i 's/^(p Point) Value() = p.Added()$/Point.Value() = 5/; s/^method() = Point.Made().Value()$/method() = Point.Value()/' "$dir/app.ce"
wait_for out "method 5" 2000 || fail "an instance method that becomes static"
wait_for out "old field" 2000 || fail "a static method called on a value"
no_internal "methods"

# A changed type applies at the next call, construction or write, and a value made before is not checked again.
wait_for out "param type" 2000 || fail "types: a parameter of the wrong type"
wait_for out "box type" 2000 || fail "types: a write of the wrong type"
wait_for out "made 2" 2000 || fail "types: a construction"
sed -i 's/^struct Box { V Int }$/struct Box { V Number }/; s/^scaled(by Int) = by \* 2$/scaled(by Number) = by * 2/' "$dir/app.ce"
wait_for out "param 3.0" 2000 || fail "types: a changed parameter type"
wait_for out "box 1.5" 2000 || fail "types: a changed field type, written"
sed -i 's/^struct Box { V Number }$/struct Box\n  V Text\nend/' "$dir/app.ce"
wait_for out "made type" 2000 || fail "types: a changed field type, at construction"
if grep -qxF "held type" "$dir/out"; then fail "types: a value made before was checked again"; fi
grep -qxF "held 1" "$dir/out" || fail "types: a value made before"
wait_for out "result type" 2000 || fail "types: a result of the wrong type"
sed -i 's/^answer() Int = 1.5$/answer() Number = 1.5/' "$dir/app.ce"
wait_for out "result 1.5" 2000 || fail "types: a changed return type"
no_internal "types"

# A changed interface applies at the next call: a value that met it stops, and the other way round. So does a method on it,
# also at a place of the loop that keeps running ("loop").
wait_for out "iface 2" 2000 || fail "interfaces: a parameter of an interface"
wait_for out "twice 2" 2000 || fail "interfaces: a method on an interface"
wait_for out "loop 2" 2000 || fail "interfaces: a method on an interface, in the running loop"
sed -i 's/^interface Sized { Size() }$/interface Sized { Size(), Weight() }/' "$dir/app.ce"
wait_for out "iface type" 2000 || fail "interfaces: a value that no longer meets it, as a type"
wait_for out "twice field" 2000 || fail "interfaces: a value that no longer meets it, for a method"
wait_for out "loop field" 2000 || fail "interfaces: a value that no longer meets it, in the running loop"
sed -i 's/^(t Tile) Size() = t.N$/(t Tile) Size() = t.N + 1\n(t Tile) Weight() = 0/; s/^(s Sized) Twice() = 2 \* s.Size()$/(s Sized) Twice() = 3 * s.Size()/' "$dir/app.ce"
wait_for out "iface 3" 2000 || fail "interfaces: a value that meets it again"
wait_for out "twice 6" 2000 || fail "interfaces: a changed method on an interface"
wait_for out "loop 6" 2000 || fail "interfaces: a value that meets it again, in the running loop"
sed -i 's/^(t Tile) Weight() = 0$/(t Tile) Weight() = 0\n(t Tile) Twice() = 100/' "$dir/app.ce"
wait_for out "twice 100" 2000 || fail "interfaces: a method of the struct, added, wins"
wait_for out "loop 100" 2000 || fail "interfaces: a method of the struct, added, wins in the running loop"
no_internal "interfaces"

# A function that only read its argument starts writing it, under a loop compiled for the old one.
wait_for out "kept 1" 2000 || fail "readKept before the change"
sed -i 's/^readKept(xs) = xs\[1\]$/defn readKept(xs)\n  xs[1] = 7\n  xs[1]\nend/' "$dir/app.ce"
wait_for out "kept 7" 2000 || fail "readKept never changed"
sleep 0.02
if grep -qxF "owner 7" "$dir/out"; then fail "a function that writes changed its caller's array"; fi

# A function that runs natively by now, as it is hot, gets its new code too.
sed -i 's/^  s \* 1$/  s * 2/' "$dir/app.ce"
wait_for out "summed 9003000" 2000 || fail "jit: native code kept the old code"

# 5. File-level statements are not rerun.
n=$(grep -cxF "start" "$dir/out")
[ "$n" -eq 1 ] || fail "5: file-level statements ran $n times"
stop


# 6. A finished program restarts when a file changes.
start done.ce "done 1"
sleep 0.1
alive "6: finished program"
# A background job of a script ignores INT from the start, and stays that way.
kill -INT "$pid"
sleep 0.05
alive "6: an INT that was ignored from the start"
sed -i 's/^Print("done 1")$/Print("done 2")/' "$dir/done.ce"
wait_for out "done 2" 2000 || fail "6: program not restarted"
stop

# 7. A package reloads as one: its files see each other through a change.
start packrun.ce "pack 1"
sed -i 's/^base() = 1$/base() = 2/' "$dir/pack/second.ce"
wait_for out "pack 2" 2000 || fail "7: a change in the other file of a package"
# Saved one after the other: the caller first, then what it calls.
sed -i 's/^Value() = base()$/Value() = added()/' "$dir/pack/first.ce"
sed -i 's/^base() = 2$/added() = 3/' "$dir/pack/second.ce"
wait_for out "pack 3" 2000 || fail "7: a new function called from the other file"
# And the other way round.
sed -i 's/^Value() = added()$/Value() = added()\nfromFirst() = 4/' "$dir/pack/first.ce"
sed -i 's/^added() = 3$/added() = fromFirst()/' "$dir/pack/second.ce"
wait_for out "pack 4" 2000 || fail "7: a new function, the other way round"
# A broken file keeps the old code of both.
sed -i 's/^added() = fromFirst()$/added() = (/' "$dir/pack/second.ce"
until grep -q "second.ce:" "$dir/err" 2>/dev/null; do sleep 0.002; done
alive "7: a broken file"
sed -i 's/^added() = ($/added() = 5/' "$dir/pack/second.ce"
wait_for out "pack 5" 2000 || fail "7: after a broken file"
# A method in another file than its struct.
sed -i 's/^Value() = added()$/Value() = Item(6).Got()/' "$dir/pack/first.ce"
wait_for out "pack 6" 2000 || fail "7: a method in another file than its struct"
# A function moved to the other file: a caller outside the package holds the cell of the old file.
sed -i '/^Value() = Item(6).Got()$/d' "$dir/pack/first.ce"
sed -i '$a Value() = Item(7).Got()' "$dir/pack/second.ce"
wait_for out "pack 7" 2000 || fail "7: a function moved to the other file"
no_internal "package"
stop

# An HTTP server: a change applies when it is idle, and under load without a failed request.
sed 's/19100/19102/' bench/http.ce > "$dir/server.ce"
get() {
  exec 3<>/dev/tcp/127.0.0.1/19102
  printf 'GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n' >&3
  tail -c 1000 <&3 | tail -1
  exec 3<&-
}
(cd "$dir" && exec "$cesia" run --watch $flags --allow net=:19102 server.ce) > "$dir/out" 2> "$dir/err" &
pid=$!
for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/19102) 2>/dev/null && break; sleep 0.05; done
[ "$(get)" = "Cesia" ] || fail "server: first answer"
sed -i 's/Body: "Cesia"/Body: "Idle"/' "$dir/server.ce"
sleep 0.15
[ "$(get)" = "Idle" ] || fail "server: a change while idle"
_build/default/bench/http_load.exe --port 19102 --connections 20 --seconds 1 > "$dir/load" 2>&1 &
load=$!
sleep 0.3
sed -i 's/Body: "Idle"/Body: "Busy"/' "$dir/server.ce"
sleep 0.2
[ "$(get)" = "Busy" ] || fail "server: a change under load"
wait "$load" || fail "server: a request failed during the reload: $(cat "$dir/load")"
stop

# 8. A window keeps its state through a reload, under SDL's dummy driver.
if pkg-config --exists sdl3 sdl3-ttf 2>/dev/null; then
  cp examples/fonts/JetBrainsMono-Regular.ttf "$dir/font.ttf"
  (cd "$dir" && SDL_VIDEODRIVER=dummy exec "$cesia" run --watch $flags --allow ffi=SDL3,ffi=SDL3_ttf window.ce) \
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
  sed -i 's/^version() = 1$/version() = 2/' "$dir/window.ce"
  latest "version 2 " 200 > /dev/null || fail "window: a changed view never ran"
  first=$(grep -m1 '^version 2 ' "$dir/out" | cut -d' ' -f3)
  [ "${first:-0}" -ge "$seen" ] || fail "window: the state restarted, from $seen to $first"
  sed -i 's/^finished() = false$/finished() = true/' "$dir/window.ce"
  latest "ended " 500 > /dev/null || fail "window: a changed update never ran"
  stop

  # 9. A stop signal ends the whole of --watch, once the program has heard of it as a quit event.
  # Job control leaves INT as it is: a background job of a script ignores it otherwise.
  open_window() {
    set -m
    # shellcheck disable=SC2086
    (cd "$dir" && SDL_VIDEODRIVER=dummy exec "$cesia" run --watch $flags --allow ffi=SDL3,ffi=SDL3_ttf quit.ce) \
      > "$dir/out" 2> "$dir/err" &
    pid=$!
    set +m
    wait_for out "open $1" 2000 || fail "$2: the window never opened"
  }
  # Waits for the process to end by itself. One that doesn't is killed: a test must not hang.
  ends() {
    local limit=$(($(date +%s%N) + 3000 * 1000000))
    while kill -0 "$pid" 2> /dev/null; do
      if [ "$(date +%s%N)" -gt "$limit" ]; then
        fail "$1: still running"
        kill -KILL "$pid"
        break
      fi
      sleep 0.01
    done
    wait "$pid" 2> /dev/null
    code=$?
    pid=""
  }
  heard() {
    grep -qxF "quit $2" "$dir/out" || fail "$1: no quit event"
    grep -qxF "ended 1" "$dir/out" || fail "$1: the program didn't end by itself"
    [ "$code" -eq 0 ] || fail "$1: exit $code"
    [ "$(grep -c '^open ' "$dir/out")" -eq 1 ] || fail "$1: the program ran again"
  }
  for signal in TERM INT; do
    open_window 1 "$signal"
    kill -"$signal" "$pid"
    ends "$signal"
    heard "$signal" 1
  done

  # A program can answer with a question. Each signal is one quit event, and none ends it by force: two can also come in a
  # row, from timeout and from cesia do, and the second one must not cut the program short.
  sed -i 's/^needed() = 1$/needed() = 2/' "$dir/quit.ce"
  open_window 1 "a question"
  kill -TERM "$pid"
  wait_for out "quit 1" 2000 || fail "a question: no quit event"
  sleep 0.1
  alive "a question"
  if grep -qxF "quit 2" "$dir/out"; then fail "a question: one signal made two quit events"; fi
  kill -TERM "$pid"
  ends "a question"
  heard "a question" 2

  # A closed window is no stop signal: --watch waits, restarts the program, and a signal still stops that one.
  sed -i 's/^needed() = 2$/needed() = 1/; s/^closing() = false$/closing() = true/' "$dir/quit.ce"
  open_window 1 "closed window"
  wait_for out "ended 1" 2000 || fail "closed window: the program didn't end"
  sleep 0.1
  alive "closed window"
  sed -i 's/^closing() = true$/closing() = false/; s/^run() = 1$/run() = 2/' "$dir/quit.ce"
  wait_for out "open 2" 2000 || fail "closed window: no restart"
  kill -TERM "$pid"
  ends "after a restart"
  grep -qxF "ended 2" "$dir/out" || fail "after a restart: the program didn't end by itself"
  [ "$code" -eq 0 ] || fail "after a restart: exit $code"

  # While it waits for a change, a signal ends it at once, even if the program left its window open.
  sed -i 's/^closing() = false$/closing() = true/; /^  sdl.Close(window)$/d' "$dir/quit.ce"
  open_window 2 "waiting"
  wait_for out "ended 2" 2000 || fail "waiting: the program didn't end"
  sleep 0.1
  alive "waiting"
  kill -TERM "$pid"
  ends "waiting"
fi

# 10. A package that uses another: what failed because the other wasn't there yet loads as soon as it is.
# Each case starts from the files of tests/reload. It waits for the first pass, the one that notes the stamps of a package.
fresh() {
  stop
  cp -r tests/reload/board.ce tests/reload/commands tests/reload/view "$dir"
  start board.ce "board old"
  sleep 0.05
}
# Waits until a file has had this many errors, then checks that no more come: a pass goes by about every millisecond.
errors() {
  local limit=$(($(date +%s%N) + 2000 * 1000000))
  until [ "$(grep -c "^$1:" "$dir/err")" -ge "$2" ] || [ "$(date +%s%N)" -gt "$limit" ]; do
    sleep 0.002
  done
  sleep 0.1
  local n
  n=$(grep -c "^$1:" "$dir/err")
  [ "$n" -eq "$2" ] || fail "$3: $n errors in $1, expected $2"
}

# Saved at once, what calls first in sorted order. A stopped program sees both in one pass, and no error is left to show.
fresh
kill -STOP "$pid"
sed -i 's/^Value() = view.Label()$/Value() = view.Added()/' "$dir/commands/commands.ce"
sed -i '$a Added() = "both"' "$dir/view/view.ce"
kill -CONT "$pid"
wait_for out "board both" 2000 || fail "10: saved at once"
errors commands/commands.ce 0 "10: saved at once"

# Saved in two steps, what calls first: its error is true for a while, and it is shown once.
fresh
sed -i 's/^Value() = view.Label()$/Value() = view.Added()/' "$dir/commands/commands.ce"
errors commands/commands.ce 1 "10: the caller saved first"
sed -i '$a Added() = "steps"' "$dir/view/view.ce"
wait_for out "board steps" 2000 || fail "10: saved in two steps"
errors commands/commands.ce 1 "10: saved in two steps"

# A chain saved at once: the program needs commands, which needs view, so one more try isn't enough.
fresh
kill -STOP "$pid"
sed -i 's/^shown() = commands.Value()$/shown() = commands.Added()/' "$dir/board.ce"
sed -i '$a Added() = view.Added()' "$dir/commands/commands.ce"
sed -i '$a Added() = "chain"' "$dir/view/view.ce"
kill -CONT "$pid"
wait_for out "board chain" 2000 || fail "10: a chain saved at once"
errors board.ce 0 "10: a chain saved at once"
errors commands/commands.ce 0 "10: a chain saved at once"

# Broken for a real reason: the old code stays and the error shows once, with no retry until something changes.
fresh
sed -i 's/^Value() = view.Label()$/Value() = view.Never()/' "$dir/commands/commands.ce"
errors commands/commands.ce 1 "10: a broken caller"
alive "10: a broken caller"
# Another change is another attempt: the error shows once more, and the old code of the caller runs on the new view.
sed -i 's/^Label() = "old"$/Label() = "kept"/' "$dir/view/view.ce"
wait_for out "board kept" 2000 || fail "10: the old code of a broken caller"
errors commands/commands.ce 2 "10: a broken caller, tried again"
sed -i 's/^Value() = view.Never()$/Value() = "fixed"/' "$dir/commands/commands.ce"
wait_for out "board fixed" 2000 || fail "10: a broken caller, fixed"
errors commands/commands.ce 2 "10: a broken caller, fixed"

# Two files of a package make one reload, and one error.
fresh
kill -STOP "$pid"
sed -i '$a Broken() = (' "$dir/view/view.ce"
sed -i '$a Touched() = 2' "$dir/view/more.ce"
kill -CONT "$pid"
errors view/view.ce 1 "10: two files of a broken package"
alive "10: two files of a broken package"
no_internal "10"
stop

[ "$failed" -eq 0 ] && echo "reload: ok"
exit "$failed"
