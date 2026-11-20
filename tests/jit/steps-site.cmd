# The limit of steps inside the recursion of deep(30), then of deep(9000), then in the loop that calls random.Float, then
# at the second and the first of two operations counted at once: the same step named by the interpreter, by native code
# from the first call and from when it gets hot. Each trace: its first frame and its last line, as deep(9000) has
# thousands.
for mode in off always hot; do
  echo "$mode:"
  for n in 60001 113000 250000 400000 400002; do
    CESIA_JIT=$mode cesia run $no_spec --limit steps=$n steps-site.ce 2>&1 | awk 'NR <= 4 { print } END { print }'
  done
done
