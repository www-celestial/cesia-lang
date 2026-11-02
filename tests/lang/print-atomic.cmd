kepler run $no_spec print-atomic.k | grep -vE '^(x \[.*\]|B)$' | wc -l
