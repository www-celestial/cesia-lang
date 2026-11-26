# The same results in each mode, a tiny young heap or not; the natives that wait stay the interpreter's, and say so.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode cesia run $no_spec natives-fibers.ce
  CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec natives-fibers.ce
done
CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run $no_spec natives-fibers.ce 2>&1 | grep -o 'interpreted: the native std/\(fiber.Receive\|sys.Sleep\)' | sort -u
