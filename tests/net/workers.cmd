# Two workers serve one port; one that dies is started again; TERM stops them all, and the supervisor ends with 0.
out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec --workers 2 --allow net=:18410,exec=sh workers.ce > "$out" 2>&1 &
pid=$!
ask() {
  exec 3<>/dev/tcp/127.0.0.1/18410 || return 1
  printf 'GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n' >&3
  tail -1 <&3
  exec 3<&-
}
for _ in $(seq 1 500); do (exec 3<>/dev/tcp/127.0.0.1/18410) 2> /dev/null && break; sleep 0.01; done
for _ in $(seq 1 100); do [ "$(pgrep -c -P $pid)" = 2 ] && break; sleep 0.02; done
echo "workers: $(pgrep -c -P $pid)"
first=$(ask)
pgrep -P $pid | grep -qx "$first" && echo "a worker answered" || echo "who answered: $first"
kill -KILL "$first"
restarted=no
for _ in $(seq 1 500); do
  [ "$(pgrep -P $pid | grep -cvx "$first")" = 2 ] && restarted=yes && break
  sleep 0.01
done
echo "another took the place of the worker that died: $restarted"
answered=yes
for _ in $(seq 1 20); do a=$(ask); [ "$a" = "$first" ] || [ -z "$a" ] && answered=no; done
echo "20 answers from live workers: $answered"
grep -c 'ended with code' "$out"
kill -TERM $pid
wait $pid
code=$?
echo "workers left: $(pgrep -c -P $pid)"
rm -f "$out"
(exit $code)
