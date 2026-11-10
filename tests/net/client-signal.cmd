out=$(mktemp)
"$root/_build/default/src/bin/main.exe" run $no_spec --allow net=127.0.0.1:18088 client-signal.ce > "$out" &
pid=$!
# The signal comes once the program is in its loop, not after a fixed wait that a busy machine can outlast; at most 5 s.
first=""
tries=0
until [ "$first" = started ] || [ $tries -ge 500 ] || ! kill -0 $pid 2> /dev/null; do
  sleep 0.01
  tries=$((tries + 1))
  read -r first < "$out"
done
# The program dies of the signal, and bash tells it ("Terminated: 15") when it sees the death before wait starts, on the
# shell's own stderr: the redirection holds kill and wait both, so that notice never reaches the output.
{ kill -TERM $pid; wait $pid; } 2> /dev/null
code=$?
cat "$out"
rm -f "$out"
(exit $code)
