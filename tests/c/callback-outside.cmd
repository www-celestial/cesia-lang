# The first line of what it says, and its exit code: an abort, with no core file.
ulimit -c 0
f="$root/_build/default/tests/c/libfixture.so"
out=$("$root/_build/default/src/bin/main.exe" run $no_spec --allow "ffi=$f" callback-outside.ce "$f" 2>&1); code=$?
echo "${out%%$'\n'*}"; (exit $code)
