# The interpreter, native code when hot, and from the first call, each under a young heap of 4,096 words, which
# collects in nearly every call of a native: the same values, and the same errors at the same sites with the same
# traces. On the typed path, machine code made at once runs the closures' frames.
for case in late error; do
  for mode in off default always; do
    echo "$case $mode:"
    CESIA_JIT=$mode OCAMLRUNPARAM=s=4k cesia run $no_spec whole-closures.ce $case
  done
done
[ -n "$no_spec" ] || [ "$(CESIA_JIT=always CESIA_JIT_SHOW=1 cesia run whole-closures.ce error 2>&1 | grep -c endfunc)" -gt 10 ] && echo "machine code runs closures"
