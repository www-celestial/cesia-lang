( ulimit -v 4000000; timeout -s KILL 10 "$root/_build/default/bin/main.exe" run $no_spec --allow read=/dev --limit memory=16M read_endless.kp ) 2>&1 | head -1 | cut -c1-60
