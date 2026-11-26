# The interpreter, native code when hot, and from the first call: the same errors at the same sites, with the same
# traces, the same Err, and the limit of steps inside a native reached at the same step.
for case in loop call err; do
  for mode in off default always; do
    echo "$case $mode:"
    CESIA_JIT=$mode cesia run $no_spec --allow env natives-errors.ce $case
  done
done
for steps in 100000 250001 361000; do
  for mode in off always; do
    echo "steps $steps $mode:"
    CESIA_JIT=$mode cesia run $no_spec --allow env --limit steps=$steps natives-errors.ce grow
  done
done
