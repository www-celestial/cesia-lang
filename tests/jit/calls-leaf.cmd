# The interpreter, then native code from the first call: the same results, and the same limits of steps and depth,
# reached at a leaf or at a call.
for mode in off always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run calls-leaf.ce
  CESIA_JIT=$mode cesia run --limit steps=150001 calls-leaf.ce
  CESIA_JIT=$mode cesia run --limit steps=150002 calls-leaf.ce
  CESIA_JIT=$mode cesia run --limit depth=9990 calls-leaf.ce
done
