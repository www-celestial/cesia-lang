"$root/_build/default/bin/main.exe" run $no_spec --allow net=127.0.0.1:18088 client_signal.kp &
pid=$!
sleep 0.2
kill -TERM $pid
wait $pid
