"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=:18089 stop.k &
pid=$!
sleep 0.15
kill -TERM $pid
wait $pid
