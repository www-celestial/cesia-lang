# HUP replaces the workers by new ones, from the file as it is now, while two clients ask without a pause, one on kept
# connections and one on a new connection for each request: not one request fails. Then a version that can't start:
# the running workers stay.
dir=$(mktemp -d)
cp workers-reload.ce "$dir/server.ce"
load="$root/_build/default/bench/http_load.exe"
ask() {
  exec 3<>/dev/tcp/127.0.0.1/18411 || return 1
  printf 'GET / HTTP/1.1\r\nHost: a\r\nConnection: close\r\n\r\n' >&3
  tail -1 <&3
  exec 3<&-
}
(cd "$dir" && exec "$root/_build/default/src/bin/main.exe" run $no_spec --workers 2 --allow net=:18411 server.ce) > "$dir/out" 2>&1 &
pid=$!
for _ in $(seq 1 500); do (exec 3<>/dev/tcp/127.0.0.1/18411) 2> /dev/null && break; sleep 0.01; done
echo "before: $(ask)"
"$load" --port 18411 --connections 20 --seconds 2 > "$dir/kept" &
kept=$!
"$load" --port 18411 --connections 4 --seconds 2 --new > "$dir/new" &
new=$!
sleep 0.5
sed -i.bak 's/version = "first"/version = "second"/' "$dir/server.ce"
kill -HUP $pid
wait $kept && echo "kept connections: no request failed" || echo "kept connections failed: $(cat "$dir/kept")"
wait $new && echo "new connections: no request failed" || echo "new connections failed: $(cat "$dir/new")"
echo "after: $(ask)"
sed -i.bak 's/version = "second"/version = (/' "$dir/server.ce"
kill -HUP $pid
for _ in $(seq 1 500); do grep -q 'running workers stay' "$dir/out" && break; sleep 0.01; done
grep -o 'the running workers stay' "$dir/out"
echo "after a broken version: $(ask)"
kill -TERM $pid
wait $pid
code=$?
rm -rf "$dir"
(exit $code)
