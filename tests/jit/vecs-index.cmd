# The same index outside, read by the interpreter, by native code once the loop is hot and by native code from the
# start: the same message, at the same read.
for bad in 4 0 -1 4611686018427387903; do
  echo "index $bad:"
  off=$(CESIA_JIT=off cesia run vecs-index.ce $bad 2>&1)
  hot=$(cesia run vecs-index.ce $bad 2>&1)
  always=$(CESIA_JIT=always cesia run vecs-index.ce $bad 2>&1)
  echo "$always"
  [ "$off" = "$always" ] && [ "$off" = "$hot" ] || echo "differs from the interpreter"
done
