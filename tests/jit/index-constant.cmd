# A list of integers replaced by a small list of floats in the loop, then read at a constant index outside it: the
# interpreter's message in each mode, where machine code named the index doubled.
for mode in off always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec index-constant.ce 2>&1 | head -1
done
