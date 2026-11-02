timeout -s KILL 5 "$root/_build/default/bin/main.exe" run $no_spec --allow net=:18101,net=127.0.0.1:18101 http_close.k
