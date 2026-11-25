# The interpreter, native code when hot, and from the first call: the same output.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec value-calls-room.ce
done
