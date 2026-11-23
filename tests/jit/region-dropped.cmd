# A region's code made again while the interpreter makes the rest of a turn its old code went back from takes the turn
# over: the interpreter's answers in each mode, where the default mode ended with an internal error.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec --limit depth=4 region-dropped.ce
done
