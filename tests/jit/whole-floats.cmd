# The interpreter, native code when hot, and from the first call, on each path: the same values.
for mode in off default always; do
  echo "$mode:"
  CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec whole-floats.ce
done
