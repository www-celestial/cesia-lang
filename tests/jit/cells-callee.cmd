# The interpreter, the default, and machine code from the first call: the same counts after k changed.
for mode in off hot always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec cells-callee.ce
done
