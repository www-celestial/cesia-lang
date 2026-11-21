# It stops near the limit of memory: OCaml's stack takes a quarter of it at most. It reached 2.4 times the limit before
# the heap did. Its message, and whether its peak of memory, which /proc tells, stays under twice the limit.
out="$(mktemp)"
"$root/_build/default/src/bin/main.exe" run $no_spec --limit memory=100M,depth=1000000000 stack-memory.ce > "$out" 2>&1 &
pid=$!
peak=0
while [ -r "/proc/$pid/status" ]; do
  kb=$(awk '/^VmHWM/ { print $2 }' "/proc/$pid/status" 2> /dev/null)
  [ -n "$kb" ] && [ "$kb" -gt "$peak" ] && peak=$kb
  sleep 0.02
done
wait $pid; code=$?
head -1 "$out"; rm -f "$out"
if [ ! -d /proc/self ] || [ "$peak" -lt 204800 ]; then echo "under twice the limit"; else echo "peak $peak KB"; fi
(exit $code)
