out=$(mktemp)
( ulimit -n 24; export LC_ALL=C; TIMEFORMAT='%U %S'; time cesia run $no_spec --allow net=own http-emfile.ce ) > "$out" 2>&1
tail -1 "$out" | awk '{ print ($1 + $2 < 0.2) ? "calm" : "spinning" }'
grep -v '^[0-9.]* [0-9.]*$' "$out"
unlink "$out"
