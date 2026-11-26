port=$("$root/_build/default/src/bin/main.exe" run --allow net=own "$root/tests/free-port.ce")
out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=:$port http-stop.ce $port > "$out" &
pid=$!
sleep 0.2
exec 3<>/dev/tcp/127.0.0.1/$port
printf 'GET / HTTP/1.1\r\nHost: a\r\n\r\n' >&3
sleep 0.05
kill -TERM $pid
head -c 15 <&3
echo
wait $pid
code=$?
cat "$out"
rm -f "$out"
(exit $code)
