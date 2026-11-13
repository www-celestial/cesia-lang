# The same output in each mode, and machine code that never falls back on the calls after the first.
for mode in off hot always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run inner-locals.ce
done
echo "fell: $(CESIA_JIT_SHOW=1 cesia run inner-locals.ce 2>&1 | grep -c 'fell$')"
