out=$(kepler run $no_spec --limit memory=16M,depth=1000000000 memory-stack.k 2>&1); code=$?
echo "${out%%$'\n'*}"; (exit $code)
