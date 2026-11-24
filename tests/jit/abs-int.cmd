# The interpreter, native code when hot, and from the first call: the same sums, and the same error.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec abs-int.ce
done
