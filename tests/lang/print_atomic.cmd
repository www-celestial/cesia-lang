kepler run $no_spec print_atomic.kp | grep -vE '^(x \[.*\]|B)$' | wc -l
