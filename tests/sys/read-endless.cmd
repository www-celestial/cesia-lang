( ulimit -v 4000000 2> /dev/null; timeout -s KILL 10 "$root/_build/default/src/bin/main.exe" run $no_spec --allow read=/dev --limit memory=16M read-endless.ce ) 2>&1 | head -1 | cut -c1-60
