cd stop
"$root/_build/default/bin/main.exe" do last_term &
pid=$!
sleep 0.15
kill -TERM $pid
wait $pid
