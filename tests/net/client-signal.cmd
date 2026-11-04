"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=127.0.0.1:18088 client-signal.ce &
pid=$!
sleep 0.2
kill -TERM $pid
wait $pid 2> /dev/null
