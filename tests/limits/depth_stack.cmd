out=$(OCAMLRUNPARAM=l=200k kepler run $no_spec --limit depth=1000000000 depth_stack.kp 2>&1); code=$?
echo "${out%%$'\n'*}"; (exit $code)
