f="$root/_build/default/tests/c/libunloadable.so"
"$root/_build/default/bin/main.exe" run $no_spec --allow "ffi=$f" unloadable.k "$f"
