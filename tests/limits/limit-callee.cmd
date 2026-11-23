# The limit of steps at f's entry, then at a self tail call of count, then the limit of depth at f's entry: the same
# trace from the interpreter, from native code at the first call, and from native code once hot.
for mode in off always hot; do
  echo "$mode:"
  for limit in steps=1 steps=3 depth=1; do
    CESIA_JIT=$mode cesia run $no_spec --limit $limit limit-callee.ce
  done
done
