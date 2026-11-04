f="$root/_build/default/tests/c/libfixture.so"
"$root/_build/default/src/bin/main.exe" run $no_spec --allow "ffi=$f" block-panics.ce "$f" 2>/dev/null
