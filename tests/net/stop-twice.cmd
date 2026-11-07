out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=:18406 stop-twice.ce > "$out" 2>&1 &
pid=$!
for _ in $(seq 1 500); do (exec 3<>/dev/tcp/127.0.0.1/18406) 2> /dev/null && break; sleep 0.01; done
exec 3<>/dev/tcp/127.0.0.1/18406
printf 'GET / HTTP/1.1\r\nHost: a\r\n\r\n' >&3
sleep 0.1
start=$SECONDS
kill -TERM $pid
sleep 0.1
kill -TERM $pid
wait $pid
code=$?
# Whole seconds, from bash itself, as a date in nanoseconds is GNU's alone: a wait would last the handler's 30.
[ $((SECONDS - start)) -lt 3 ] && echo "ended at once" || echo "waited"
exec 3<&-
cat "$out"
rm -f "$out"
(exit $code)
