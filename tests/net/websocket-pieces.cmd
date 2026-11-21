# The server side of WebSocket, a frame of a megabyte that a client sends 128 bytes at a time: the server reads it into one
# buffer, joined once, where it copied all it had at each piece, 4 GB in all. Its time on the processor tells.
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp websocket-pieces.ce websocket-pieces-client.ce "$dir"
cd "$dir"
LC_NUMERIC=C TIMEFORMAT='%U %S'
{ time cesia run $no_spec --allow net=:18463 websocket-pieces.ce > server.out; } 2> cpu.txt &
server=$!
for _ in $(seq 100); do [ -s server.out ] && break; sleep 0.05; done
cesia run $no_spec --allow net=127.0.0.1:18463 websocket-pieces-client.ce
wait $server
awk '{ s = $1 + $2; print (s < 0.8 ? "the server took less than 0.8 s" : "the server took " s " s") }' cpu.txt
