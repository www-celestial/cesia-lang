cd stop
"$root/_build/default/bin/main.exe" do last_int &
pid=$!
sleep 0.15
kill -INT $pid
wait $pid
