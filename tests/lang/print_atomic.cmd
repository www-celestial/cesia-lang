kepler run $no_spec print_atomic.k | grep -vE '^(x \[.*\]|B)$' | wc -l
