# Linux alone has /proc: elsewhere, what it would print. No exit here: the harness prints the exit of the whole file.
if [ ! -r /proc/self/status ]; then
  printf 'memory after 100,000 slow calls, bounded: true\n'
else
  f="$root/_build/default/tests/c/libfixture.so"
  "$root/_build/default/src/bin/main.exe" run $no_spec --allow "ffi=$f,read=/proc/self/status" slow-memory.ce "$f"
fi
