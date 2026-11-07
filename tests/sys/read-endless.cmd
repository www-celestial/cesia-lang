( ulimit -v 4000000 2> /dev/null; cesia run --allow exec "$root/tests/time-limit.ce" 10 run $no_spec --allow read=/dev --limit memory=16M read-endless.ce ) 2>&1 | head -1 | cut -c1-60
