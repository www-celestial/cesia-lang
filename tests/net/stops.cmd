out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec stops.ce > "$out" 2>&1 &
pid=$!
first=""
for _ in $(seq 1 500); do read -r first < "$out"; [ "$first" = ready ] && break; sleep 0.01; done
sleep 0.05
kill -TERM $pid
wait $pid
code=$?
cat "$out"
rm -f "$out"
(exit $code)
