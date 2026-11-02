out=$(kepler run $no_spec --limit depth=100 depth-after-big.k 2>&1); code=$?
echo "$out" | grep -E '^(big|small)|Limit|more$' | sed 's/^ *//'; (exit $code)
