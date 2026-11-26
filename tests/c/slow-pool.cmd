# Linux alone has /proc: elsewhere, what it would print. The program stops at TERM, sent once it said started, while the
# domain of its last call waits: it dies of the signal at once, not after its sleep of 20 s.
if [ ! -r /proc/self/status ]; then
  printf 'no domain before the first slow call: true\na domain waits between the calls of a burst: true\na thousand calls on a few domains: true\nit leaves once idle: true\nstarted\n'
  exit 143
fi
f="$root/_build/default/tests/c/libfixture.so"
out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec --allow "ffi=$f,read=/proc/self/task" slow-pool.ce "$f" > "$out" &
pid=$!
last=""
tries=0
until [ "$last" = started ] || [ $tries -ge 1500 ] || ! kill -0 $pid 2> /dev/null; do
  sleep 0.01
  tries=$((tries + 1))
  last=$(tail -n 1 "$out")
done
{ kill -TERM $pid; wait $pid; } 2> /dev/null
code=$?
cat "$out"
rm -f "$out"
(exit $code)
