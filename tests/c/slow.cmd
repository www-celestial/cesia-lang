f="$root/_build/default/tests/c/libfixture.so"
CESIA_CORES=1 "$root/_build/default/src/bin/main.exe" run $no_spec --allow "ffi=$f" slow.ce "$f"
