# The limit of steps at twice's entry, called back by the native of quad.Integral; the limit of depth at the entry of
# add, called back by list.Reduce, of the method Box.Get, of twice through a value, and of twice as a fiber's first
# call: the same trace from the interpreter, from native code at the first call, and from native code once hot.
for mode in off always hot; do
  echo "$mode:"
  for run in "native steps=13" "std depth=2" "method depth=1" "held depth=1" "fiber depth=1"; do
    set -- $run
    CESIA_JIT=$mode cesia run $no_spec --limit $2 limit-callers.ce $1
  done
done
