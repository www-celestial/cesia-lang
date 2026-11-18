# The interpreter, native code from the first call, then from when it gets hot: the same results.
for mode in off always hot; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec calls-none.ce
done
