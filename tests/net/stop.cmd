"$root/_build/default/bin/main.exe" run $no_spec --allow net=:18089 stop.kp &
pid=$!
sleep 0.15
kill -TERM $pid
wait $pid
