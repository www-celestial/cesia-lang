f="$root/_build/default/tests/c/libfixture.so"
"$root/_build/default/bin/main.exe" run $no_spec --allow "ffi=$f" block_ptr.kp "$f"
