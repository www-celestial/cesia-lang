cd stop
# The last task is cesia do itself: the TERM reaches its program once, and the code is the program's own, 0 here.
"$root/_build/default/src/bin/main.exe" do trapped &
pid=$!
sleep 0.15
kill -TERM $pid
wait $pid
