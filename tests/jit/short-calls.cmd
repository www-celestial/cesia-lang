# A function made native as a whole, whose calls from the interpreter make fewer steps than coming into native code and
# going back costs, as one with a loop of 2 turns, or a recursion that gives back at once: its calls go back to the
# interpreter, which keeps its code. When they get longer, 32 turns, or fib(8), its code takes them again at its next
# try, and no unit is made again. The default mode, and the same answers as the interpreter's.
show() { CESIA_JIT=hot CESIA_JIT_SHOW=1 cesia run short-calls.ce "$@" 2>&1 > /dev/null | grep -E 'calls are|: module$' | sed 's/^mu[0-9]*_: module$/a unit made/'; }
echo "short calls:"
show
echo "longer calls after:"
show longer
for mode in off hot; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec short-calls.ce longer
done
