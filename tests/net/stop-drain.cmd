out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=:18405 stop-drain.ce > "$out" 2>&1 &
pid=$!
for _ in $(seq 1 500); do (exec 3<>/dev/tcp/127.0.0.1/18405) 2> /dev/null && break; sleep 0.01; done
# A kept connection that has asked once and waits, and a request in progress when the signal comes.
exec 4<>/dev/tcp/127.0.0.1/18405
printf 'GET /idle HTTP/1.1\r\nHost: a\r\n\r\n' >&4
exec 3<>/dev/tcp/127.0.0.1/18405
printf 'GET /slow HTTP/1.1\r\nHost: a\r\n\r\n' >&3
sleep 0.15
kill -TERM $pid
sleep 0.1
(exec 5<>/dev/tcp/127.0.0.1/18405) 2> /dev/null && echo "a new connection was accepted" || echo "no new connection"
tr -d '\r' <&3 | grep -E '^(HTTP|connection|done)'
# The kept connection gets one more request, as the server stops, and its response says that the connection closes.
printf 'GET /last HTTP/1.1\r\nHost: a\r\n\r\n' >&4
tr -d '\r' <&4 | grep -E '^(HTTP|connection|done)'
exec 3<&- 4<&-
wait $pid
code=$?
cat "$out"
rm -f "$out"
(exit $code)
