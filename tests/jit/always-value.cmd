# Under CESIA_JIT=always a loop is lowered at its start, before any step, when its call through a value has met no
# function yet: it is lowered again after its first steps, then runs as machine code. A function it didn't bet on goes
# back to the interpreter, and the loop is made again for both; one whose call met more functions than it remembers stays
# interpreted, refused twice. Three units, and the interpreter's answers.
echo "units: $(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run always-value.ce 2>&1 > /dev/null | grep -c ': module$')"
for mode in off always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec always-value.ce
done
