# Each way: the program gets TERM once its child runs; the child must be gone after it.
for serve in no yes; do
  out=$(mktemp)
  SERVE=$serve "$root/_build/default/src/bin/main.exe" run $no_spec --allow exec=sh,env=SERVE,net=:18407 stop-children.ce > "$out" 2>&1 &
  pid=$!
  line=""
  for _ in $(seq 1 500); do read -r line < "$out"; [ -n "$line" ] && break; sleep 0.01; done
  child=${line#child }
  [ "$serve" = yes ] && for _ in $(seq 1 500); do (exec 3<>/dev/tcp/127.0.0.1/18407) 2> /dev/null && break; sleep 0.01; done
  kill -TERM $pid
  wait $pid
  code=$?
  sleep 0.05
  kill -0 "$child" 2> /dev/null && echo "serve=$serve: the child still runs" || echo "serve=$serve: the child is gone"
  sed 's/^child [0-9]*$/child/' "$out"
  echo "exit $code"
  rm -f "$out"
done
