# A loop whose runs make fewer steps than coming into native code and going back costs, as one of 2 turns in a function
# called often, stays the interpreter's and no unit is made for it; when its runs get longer, 32 turns, it gets its unit.
# The default mode, and the same answers as the interpreter's.
units() { CESIA_JIT=hot CESIA_JIT_SHOW=1 cesia run short-runs.ce "$@" 2>&1 > /dev/null | grep -c ': module$'; }
echo "units for runs of 2 turns: $(units)"
echo "units when runs of 32 turns follow: $(units longer)"
for mode in off hot; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec short-runs.ce longer
done
