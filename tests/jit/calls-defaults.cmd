# The interpreter, native code when hot, and from the first call: the same results, and the same limits of steps and
# depth, reached at a callee's step, in its loop, and in a loop of calls; then the other path.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec calls-defaults.ce
  for limit in steps=20000 steps=60000 steps=100000 depth=1; do
    CESIA_JIT=$mode cesia run $no_spec --limit $limit calls-defaults.ce 2>&1 | tail -5
  done
done
