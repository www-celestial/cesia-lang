"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=own stop.ce &
pid=$!
sleep 0.15
kill -TERM $pid
wait $pid
