port=$("$root/_build/default/src/bin/main.exe" run --allow net=own "$root/tests/free-port.ce")
"$root/_build/default/src/bin/main.exe" run $no_spec permissions.ce $port 2>/dev/null
