# The interpreter, native code from the first run, then from when it gets hot: each test runs once, and the limit of
# steps names the same step, at the turn of spin's for after the test of its while, at the next turn of the for inside,
# and at the last step of the program, which has printed all it prints.
for mode in off always hot; do
  echo "$mode:"
  for n in 22 23 216256; do
    CESIA_JIT=$mode cesia run $no_spec --limit steps=$n while-test.ce
  done
done
