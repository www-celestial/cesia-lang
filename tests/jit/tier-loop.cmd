# The interpreter, the default, and machine code from the first run, level 2 from the end of its first quantum of steps:
# the same output. Under CESIA_JIT=always, the swap is always there: one unit, one level 2.
for mode in off hot always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run tier-loop.ce
done
echo "level 2: $(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run tier-loop.ce 2>&1 | grep -c '^jit: level 2$')"
