# A parameter left to its default holds its default in machine code too, which the interpreter computes as a frame
# starts and native code entered there did not, reading what an earlier frame left in the slot: the interpreter's answers
# in each mode. Then, on the typed path, where a call that gives every argument has a version of its own, a limit of depth
# that counts the frame of a self tail call into it.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec defaults.ce
  CESIA_JIT=$mode cesia run --limit depth=5 defaults-depth.ce 2>&1 | head -5
done
