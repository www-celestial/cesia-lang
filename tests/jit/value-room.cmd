# The interpreter, native code when hot, and from the first call: the same output, the same limit of steps at the same
# call, wherever native code was short of room.
for limit in 2600001 4000000 100000000; do
  for mode in off default always; do
    echo "$mode, steps $limit:"
    CESIA_JIT=$mode cesia run $no_spec --limit steps=$limit value-room.ce 2>&1 | head -8
  done
done
