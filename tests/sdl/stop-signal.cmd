out=$(mktemp)
trap 'rm -f "$out"' EXIT
SDL_VIDEODRIVER=dummy "$root/_build/default/src/bin/main.exe" run $no_spec --allow ffi=SDL3,ffi=SDL3_ttf stop-signal.k > "$out" 2>&1 &
pid=$!
line() {
  for _ in $(seq 1 400); do
    grep -qxF "$1" "$out" && return
    sleep 0.01
  done
}
line open
kill -TERM "$pid"
line closed
kill -TERM "$pid"
wait "$pid" 2> /dev/null
code=$?
cat "$out"
(exit "$code")
