# A port where nothing listens: one that the system gave free a moment before.
port=$(cesia run --allow net=own "$root/tests/free-port.ce")
cesia run $no_spec --allow net=127.0.0.1:$port refused.ce $port
