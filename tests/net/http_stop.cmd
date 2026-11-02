"$root/_build/default/bin/main.exe" run $no_spec --allow net=:18095 http_stop.k &
pid=$!
sleep 0.2
exec 3<>/dev/tcp/127.0.0.1/18095
printf 'GET / HTTP/1.1\r\nHost: a\r\n\r\n' >&3
sleep 0.05
kill -TERM $pid
head -c 15 <&3
echo
wait $pid
