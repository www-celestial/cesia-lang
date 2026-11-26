# The interpreter, native code when hot, and from the first call: the same values, the same error.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec value-results.ce
done
