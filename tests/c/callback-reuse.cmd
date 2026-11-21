f="$root/_build/default/tests/c/libfixture.so"
out=$("$root/_build/default/src/bin/main.exe" run $no_spec --limit memory=30M --allow "ffi=$f" callback-reuse.ce "$f" 2>&1); code=$?
echo "$out" | head -2; (exit $code)
