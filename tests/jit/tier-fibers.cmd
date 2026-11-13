# The interpreter, the default, and machine code from the first call: the same results.
for mode in off hot always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run tier-fibers.ce
done
