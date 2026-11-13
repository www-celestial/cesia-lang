# The interpreter, the default, and machine code from the first run: the same sum, whichever level a guard fails in.
for mode in off hot always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run tier-bail.ce
done
echo "level 2: $(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run tier-bail.ce 2>&1 | grep -c '^jit: level 2$')"
