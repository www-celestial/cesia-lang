out=$(OCAMLRUNPARAM=l=200k cesia run $no_spec --limit depth=1000000000 depth-stack.ce 2>&1); code=$?
echo "${out%%$'\n'*}"; (exit $code)
