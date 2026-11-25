# The interpreter and native code from the first turn: the same values, and the same stop at the ! of an Err or of a
# value that is no result, after the turns that ran as machine code; then the other path. Each loop lowers.
for f in bang bang-value; do
  echo "$f units: $(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run $f.ce 2>&1 > /dev/null | grep -c ': module$')"
  for mode in off always; do
    echo "$mode:"
    CESIA_JIT=$mode cesia run $no_spec $f.ce 2>&1
  done
done
