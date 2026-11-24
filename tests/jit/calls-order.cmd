# The interpreter, native code when hot, and from the first call: the same sum, and the same first error.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec calls-order.ce
done
