# Integers against floats compared exactly in machine code, as the interpreter does: the interpreter's answers, in each
# mode.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec exact-compare.ce
done
